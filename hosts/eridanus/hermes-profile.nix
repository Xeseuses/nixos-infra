# hosts/eridanus/hermes-profile.nix
#
# Declares ONE secondary Hermes profile (coder, researcher, home, ...) as a
# real systemd SYSTEM service running its own `gateway run` process.
#
# WHY A SEPARATE PROCESS PER PROFILE (history, read before changing this):
#
#   This session originally tried the opposite approach: rely on Corvus's
#   `gateway.multiplex_profiles = true` (already set in hermes-agent.nix)
#   to have ONE process serve every profile, and render each profile's
#   config.yaml/SOUL.md/.env into ~/.hermes/profiles/<name>/ with no
#   separate service at all (see hermes-profile-files.nix, now unused for
#   this purpose).
#
#   That was abandoned after hands-on verification on eridanus showed:
#     - `hermes profile list` / `hermes gateway list` both reported
#       coder/researcher/home as "stopped" / "not running" after a clean
#       service restart, despite their config.yaml/SOUL.md/.env existing
#       correctly on disk (verified via `ls -la`, correct ownership,
#       correct timestamps matching the activation run).
#     - coder/researcher were confirmed OFFLINE in Discord at the same time.
#     - Direct inspection of the installed hermes_cli source (v0.17.0,
#       2026.6.19) on eridanus CONFIRMED the root cause precisely:
#         - `hermes_cli/profiles.py` defines `profiles_to_serve(multiplex)`,
#           which correctly returns the default profile plus every valid
#           named profile when multiplex=True — the logic is correct.
#         - `hermes_cli/gateway.py` defines `_guard_named_profile_under_
#           multiplexer`, which correctly reads `gateway.multiplex_profiles`
#           from config and refuses a second process for an
#           already-multiplexed profile.
#         - BUT: `grep -rn "profiles_to_serve"` across the ENTIRE installed
#           package tree returns zero call sites anywhere. The function
#           that would actually bring secondary profiles online is dead
#           code in this build — defined, never invoked. The guard that
#           protects against double-binding is real and active; the
#           feature it's guarding does not run.
#     - This means `gateway.multiplex_profiles: true` is accepted by config
#       parsing, validated by the guard, and silently does nothing for
#       secondary profiles — no error, no warning, on any installed
#       version's worth of `hermes status`/`doctor`/`gateway list`/`profile
#       list` output we could find. Likely worth filing upstream.
#
#   Given that, the only architecture confirmed to actually work on this
#   install is the one documented in "Profiles: Running Multiple Agents"
#   (not "Running Many Gateways at Once"): one process per profile, each
#   under its own systemd-supervised gateway, each with its own bot token.
#   This file implements exactly that.
#
# Why a SYSTEM service and not a systemd --user service (unchanged from the
# original imperative setup's hard-won lesson, finding #7 in the original
# Discord rollout notes): `systemctl --user` sessions tied to a `sudo -u
# hermes -i` login are prone to DBUS_SESSION_BUS_ADDRESS / XDG_RUNTIME_DIR
# races. A system unit with `User = "hermes"` has neither problem.
#
# IMPORTANT — Corvus's own multiplex_profiles flag: leave it set to `false`
# explicitly once this file is wired in (see hermes-agent.nix), rather than
# leaving the dead `true` value in place. A flag that's confirmed inert
# should not look "on" in the config — a future reader (human or agent)
# has no way to know it's inert just by reading the YAML, and a future
# Hermes upgrade could make the flag live again, silently changing
# behavior a second time.
#
# USAGE (from hosts/eridanus/hermes-agent.nix):
#
#   imports = [
#     (import ./hermes-profile.nix {
#       profileName = "coder";
#       inherit pkgs lib config;
#       hermesPackage = <the same package hermes-agent's own module resolves
#                         to, with the messaging extra — see note below>;
#       configYaml = ./hermes-profiles/coder/config.yaml;
#       soulMd = ./hermes-profiles/coder/SOUL.md;
#       envSecretPath = config.sops.secrets."hermes-coder-env".path;
#     })
#   ];
#
# NOTE on hermesPackage: the real `hermes-agent.nixosModules.default` takes
# `extraDependencyGroups = [ "messaging" ]` and resolves its own package
# internally — that exact derivation isn't directly exposed as a plain
# option value as of the version of the module checked. The pragmatic
# choice here is to reference the SAME nix store path the running
# `hermes-agent.service` actually uses (visible via `systemctl status
# hermes-agent.service` → CGroup path, e.g.
# /nix/store/<hash>-hermes-agent-env/bin/hermes) rather than re-deriving the
# package independently, so secondary profiles are guaranteed to run the
# identical binary/version as Corvus. See hermes-agent.nix for how this is
# threaded through — confirm the store path matches after every
# `nixos-rebuild switch` that updates hermes-agent, since a flake update
# could change the hash and silently leave secondary profiles on stale code
# if this isn't kept in sync.
#
# NOTE on config.yaml mutability: this is a FLAT OVERWRITE on every
# activation, not a deep merge. Any runtime self-modification the agent
# makes to its own config.yaml will be discarded on the next
# `nixos-rebuild switch`. Accepted tradeoff for reproducibility; flag it if
# coder/researcher start behaving like they "forgot" a runtime config
# change after a rebuild.

{ profileName
, config
, lib
, pkgs
, hermesPackage
, configYaml
, soulMd
, envSecretPath
, corvusHermesHome ? "/var/lib/hermes/.hermes"
, hermesUser ? "hermes"
, hermesGroup ? "hermes"
, extraServiceConfig ? { }
}:

let
  hermesHome = "${corvusHermesHome}/profiles/${profileName}";
  serviceName = "hermes-${profileName}";
in
{
  # ---------------------------------------------------------------------
  # HERMES_HOME for this profile + generated config/SOUL files
  # ---------------------------------------------------------------------
  # We only ever touch our own profiles/<name>/ subtree — never the parent
  # corvusHermesHome itself, which belongs to the real hermes-agent module.
  systemd.tmpfiles.rules = [
    "d ${corvusHermesHome}/profiles 0750 ${hermesUser} ${hermesGroup} - -"
    "d ${hermesHome} 0750 ${hermesUser} ${hermesGroup} - -"
  ];

  system.activationScripts."hermesProfileFiles-${profileName}" = {
    deps = [ "users" "groups" "setupSecrets" ];
    text = ''
      mkdir -p "${hermesHome}"
      install -m 0640 -o ${hermesUser} -g ${hermesGroup} ${configYaml} "${hermesHome}/config.yaml"
      install -m 0640 -o ${hermesUser} -g ${hermesGroup} ${soulMd} "${hermesHome}/SOUL.md"
      install -m 0600 -o ${hermesUser} -g ${hermesGroup} ${envSecretPath} "${hermesHome}/.env"
    '';
  };

  # ---------------------------------------------------------------------
  # The systemd SYSTEM service itself — one real process for this profile
  # ---------------------------------------------------------------------
  systemd.services.${serviceName} = lib.recursiveUpdate {
    description = "Hermes Agent gateway — profile '${profileName}'";
    after = [ "network-online.target" "hermes-agent.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HERMES_HOME = hermesHome;
      # Deliberately NOT setting HERMES_MANAGED here, by design — this
      # profile is not managed by the upstream module's guard system, and
      # `hermes -p ${profileName} ...` should remain usable for ad-hoc
      # debugging without hitting a "managed by NixOS" error that doesn't
      # actually apply to this code path.
    };

    serviceConfig = {
      Type = "simple";
      User = hermesUser;
      Group = hermesGroup;
      WorkingDirectory = hermesHome;
      ExecStart = "${hermesPackage}/bin/hermes gateway run";
      # NOTE: --force deliberately OMITTED here, unlike the original
      # imperative setup. --force exists specifically to bypass the
      # multiplexer's conflict guard (_guard_named_profile_under_
      # multiplexer) — since Corvus's multiplex_profiles is now explicitly
      # set to false (see hermes-agent.nix), that guard's condition (c)
      # ("default config has multiplexing on") is false, so the guard
      # exits early and never fires. --force should not be needed. If a
      # fresh deploy unexpectedly hits the multiplexer-conflict error
      # again, that means Corvus's flag wasn't actually turned off where
      # this process reads it from — fix that, don't just re-add --force.

      Restart = "always";
      RestartSec = 5;

      # Matches Corvus's own fix for the same underlying issue (drain_timeout
      # is 180s on this Hermes version, so TimeoutStopSec must exceed it —
      # see hosts/eridanus/hermes-agent.nix's own TimeoutStopSec override,
      # and the original Discord rollout's open item #8 flagging this same
      # warning for the hand-written user services).
      TimeoutStopSec = "210s";

      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  } extraServiceConfig;
}


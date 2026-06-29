# hosts/eridanus/hermes-profile-files.nix
#
# Declaratively renders one secondary Hermes profile's config.yaml, SOUL.md,
# and .env into place under Corvus's multiplexer-served profile tree.
#
# IMPORTANT — this replaces an earlier draft (hermes-profile.nix, retired)
# that created a separate systemd SYSTEM service per profile running
# `hermes gateway run --force`. That design was wrong for this host: Corvus's
# existing hermes-agent.nix already sets `gateway.multiplex_profiles = true`,
# which means Corvus's ONE gateway process is the sole inbound process for
# EVERY profile on the box. A second process for `coder` would double-bind
# coder's Discord token against the same gateway that's already serving it
# — exactly the failure case Hermes' own multi-profile-gateways docs warn
# about ("a named-profile `hermes gateway start`/`run` is a hard error...
# the multiplexer is the single inbound process; a second profile gateway
# would double-bind that profile's platforms").
#
# Per those same docs: "every profile keeps its config inside its own
# directory: ~/.hermes/profiles/<name>/{.env,config.yaml,SOUL.md}" — and
# multiplexing does not change that layout at all. So the ONLY Nix work
# a secondary profile needs is making sure those three files exist with
# the right content in the right place before Corvus's gateway starts (or
# restarts) and enumerates profiles. No new service, no new process.
#
# USAGE (from hosts/eridanus/hermes-agent.nix):
#
#   imports = [
#     (import ./hermes-profile-files.nix {
#       profileName = "coder";
#       inherit config lib;
#       configYaml = ./hermes-profiles/coder/config.yaml;
#       soulMd = ./hermes-profiles/coder/SOUL.md;
#       envSecretPath = config.sops.secrets."hermes/coder-env".path;
#     })
#   ];
#
# Result on disk:
#   /var/lib/hermes/.hermes/profiles/<name>/
#     config.yaml   (copied from configYaml — flat overwrite on every activation)
#     SOUL.md        (copied from soulMd — flat overwrite on every activation)
#     .env           (copied from the decrypted sops secret at envSecretPath)
#
# This activation script runs BEFORE hermes-agent's own systemd service
# (re)starts, via the `before` dependency on systemd's reload, so a profile
# that's brand new on this rebuild is fully populated by the time Corvus's
# multiplexer next enumerates profiles. See the validation checklist for
# how to confirm the multiplexer actually picked it up (`hermes profile
# list`, `hermes gateway list`) — this has NOT been verified against a real
# host yet, only derived from documented behavior.
#
# NOTE on .env: unlike config.yaml/SOUL.md (plain repo files), the profile's
# .env contains secrets and must come from a decrypted sops secret path, not
# a repo-tracked file. envSecretPath should point at a per-profile sops
# secret (see hermes-agent.nix for how Corvus's own hermes/env secret is
# declared) — do NOT reuse Corvus's own hermes/env secret here. Per the
# multi-profile-gateways docs, each profile needs its OWN bot token per
# platform; reusing a token across profiles is a hard error at gateway
# startup ("token-conflict safety"), not silently allowed.

{ profileName
, config
, lib
, configYaml
, soulMd
, envSecretPath
, corvusHermesHome ? "/var/lib/hermes/.hermes"
, hermesUser ? "hermes"
, hermesGroup ? "hermes"
}:

let
  profileDir = "${corvusHermesHome}/profiles/${profileName}";
in
{
  systemd.tmpfiles.rules = [
    "d ${corvusHermesHome}/profiles 0750 ${hermesUser} ${hermesGroup} - -"
    "d ${profileDir} 0750 ${hermesUser} ${hermesGroup} - -"
  ];

  system.activationScripts."hermesProfileFiles-${profileName}" = {
    # Must run after the real hermes-agent module's own activation (which
    # creates corvusHermesHome itself) and after sops has decrypted secrets
    # into /run/secrets, but BEFORE hermes-agent's systemd service restarts.
    #
    # VERIFIED (not assumed): sops-nix's general-purpose secret-decryption
    # activation snippet is named exactly "setupSecrets" (confirmed via
    # sops-nix's own issue tracker, which shows this snippet name directly
    # in stage-2-init journal output: "Activation script snippet
    # 'setupSecrets' failed"). This is distinct from "setupSecretsForUsers",
    # which is a SEPARATE, earlier-running snippet only for secrets flagged
    # `neededForUsers = true` (e.g. a users.users.<x>.passwordFile) — not
    # relevant here, since envSecretPath is an ordinary file secret with no
    # such flag. "setupSecrets" is the correct dependency for this case.
    deps = [ "users" "groups" "setupSecrets" ];
    text = ''
      mkdir -p "${profileDir}"

      install -m 0640 -o ${hermesUser} -g ${hermesGroup} \
        ${configYaml} "${profileDir}/config.yaml"

      install -m 0640 -o ${hermesUser} -g ${hermesGroup} \
        ${soulMd} "${profileDir}/SOUL.md"

      install -m 0600 -o ${hermesUser} -g ${hermesGroup} \
        ${envSecretPath} "${profileDir}/.env"
    '';
  };
}


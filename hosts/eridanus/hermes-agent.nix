# Hermes Agent orchestrator — runs on eridanus. No local inference; calls
# out to horologium (primary), andromeda + caelum (auxiliary tasks),
# andromeda (HA-delegation fast path), and Anthropic (fallback only).
#
# Requires: inputs.hermes-agent.nixosModules.default in eridanus's flake
# module list.
#
# Requires secrets/secrets.yaml to contain, nested under a real `hermes:`
# YAML key (not a flat "hermes/env" string key):
#   hermes:
#       env: |
#           ANTHROPIC_API_KEY=...
#           TELEGRAM_BOT_TOKEN=...
#           TELEGRAM_ALLOWED_USERS=...
#           HASS_TOKEN=...
#           HASS_URL=http://10.40.40.115:8123
#           DISCORD_BOT_TOKEN=...
#           DISCORD_ALLOWED_USERS=...
#
# SECONDARY PROFILES (coder, researcher, home).
#
# ARCHITECTURE NOTE — read before changing this section: an earlier version
# of this file relied on Corvus's `gateway.multiplex_profiles` to have ONE
# process serve every profile, with no separate systemd unit per secondary
# profile. That was abandoned after hands-on verification on eridanus
# (June 29) proved it doesn't work on the installed Hermes version
# (v0.17.0, 2026.6.19): direct inspection of the installed hermes_cli
# source confirmed `profiles_to_serve()` — the function that would
# enumerate and serve secondary profiles under a multiplexer — is defined
# in hermes_cli/profiles.py but has ZERO call sites anywhere in the
# installed package. The guard that PREVENTS double-binding
# (`_guard_named_profile_under_multiplexer` in hermes_cli/gateway.py)
# is real and active; the feature it protects is dead code. The flag is
# accepted, validated, and silently does nothing — no error anywhere.
#
# Given that, multiplex_profiles is explicitly set to `false` below (see
# the gateway = { ... } block) rather than left as a misleadingly-"on"
# dead flag, and each secondary profile instead gets its own real systemd
# SYSTEM service via hermes-profile.nix — one process per profile, each
# with its own bot token, which IS the documented and confirmed-working
# architecture ("Profiles: Running Multiple Agents").
#
# Each secondary profile needs its OWN sops secret for .env — per Hermes'
# docs, reusing a bot token across profiles is a hard error at gateway
# startup, so do NOT point more than one profile's secret at the same
# token.
#
# secrets/secrets.yaml additionally needs, alongside the existing `hermes:`
# key (these are new, separate top-level keys — NOT nested under `hermes:`,
# to keep each profile's secret independently rotatable/revokable):
#   hermes-coder-env: |
#       DEEPSEEK_API_KEY=...
#       DISCORD_BOT_TOKEN=...
#       DISCORD_ALLOWED_USERS=...
#   hermes-researcher-env: |
#       DEEPSEEK_API_KEY=...
#       DISCORD_BOT_TOKEN=...
#       DISCORD_ALLOWED_USERS=...
#   hermes-home-env: |
#       # home's model (andromeda Ollama) needs no API key — Telegram only,
#       # no Discord. Add TELEGRAM_BOT_TOKEN/TELEGRAM_ALLOWED_USERS here if
#       # home gets its own bot rather than reusing the original imperative
#       # setup's arrangement — confirm which is intended before deploying.
#
# CONFIRMED on eridanus (June 29): the real hermes-agent module's own
# ExecStart resolves to a direct binary call with no wrapper script —
# `/nix/store/<hash>-hermes-agent-<version>/bin/hermes gateway`. We derive
# hermesPackage below by reading that same ExecStart back out of
# config.systemd.services.hermes-agent.serviceConfig and stripping it down
# to the package root, so secondary profiles are GUARANTEED to run the
# exact same binary/version as Corvus, with no separate derivation to keep
# in sync by hand.

{ config, lib, pkgs, ... }:

let
  # Extract the package root from Corvus's own already-resolved ExecStart,
  # e.g. "/nix/store/<hash>-hermes-agent-<version>/bin/hermes gateway"
  # -> "/nix/store/<hash>-hermes-agent-<version>"
  # Confirmed shape via `systemctl show hermes-agent.service -p ExecStart`
  # on eridanus: a direct binary path, no shell wrapper, so this string
  # manipulation is safe — re-verify if a future hermes-agent module
  # version changes how it sets ExecStart (e.g. switches to a wrapper
  # script), since this extraction would then need to unwrap one more
  # layer.
  corvusExecStart = config.systemd.services.hermes-agent.serviceConfig.ExecStart;
  hermesPackageRoot =
    let
      # ExecStart can be a string or a list depending on how the module set
      # it; normalize to a single string first.
      execStartStr =
        if builtins.isList corvusExecStart
        then builtins.head corvusExecStart
        else corvusExecStart;
      # CORRECTNESS FIX (caught via real dry-build error): the first draft
      # used `lib.strings.lastIndexOf`, which does not exist in nixpkgs —
      # confirmed by checking the actual lib/strings.nix source rather than
      # guessing a second time. nixpkgs' lib.strings has no generic
      # "index of substring" helper at all; `splitString` is the correct,
      # confirmed-real tool for this: split on the fixed marker "/bin/hermes"
      # and take everything before it. Since a real package path never
      # contains "/bin/hermes" as a substring of its own hash/name (Nix
      # store paths are a fixed hash + derivation name, not arbitrary text),
      # this is safe — splitString returns exactly 2 pieces for the expected
      # input shape, and we take the first.
      parts = lib.strings.splitString "/bin/hermes" execStartStr;
    in
    if builtins.length parts < 2
    then throw "hermes-agent.nix: could not find '/bin/hermes' in hermes-agent.service's ExecStart (${execStartStr}) — the real module's unit shape may have changed; update hermesPackageRoot's extraction logic in this file."
    else builtins.elemAt parts 0;
  hermesPackage = pkgs.runCommand "hermes-agent-package-ref" { } ''
    ln -s ${lib.escapeShellArg hermesPackageRoot} $out
  '';
  # NOTE: the runCommand indirection above exists only so hermesPackage is
  # a real Nix path/derivation usable in string interpolation
  # (${hermesPackage}/bin/hermes) downstream in hermes-profile.nix, rather
  # than a bare string that Nix would refuse to interpolate the same way.
  # This has NOT been validated with a real dry-build yet — if this
  # specific trick errors, the simpler fix is to change hermes-profile.nix
  # to accept hermesPackageRoot as a plain string and build the ExecStart
  # command with string concatenation instead of path interpolation.

  coderProfile = import ./hermes-profile.nix {
    profileName = "coder";
    inherit config lib pkgs hermesPackage;
    configYaml = ./hermes-profiles/coder/config.yaml;
    soulMd = ./hermes-profiles/coder/SOUL.md;
    envSecretPath = config.sops.secrets."hermes-coder-env".path;
  };
  researcherProfile = import ./hermes-profile.nix {
    profileName = "researcher";
    inherit config lib pkgs hermesPackage;
    configYaml = ./hermes-profiles/researcher/config.yaml;
    soulMd = ./hermes-profiles/researcher/SOUL.md;
    envSecretPath = config.sops.secrets."hermes-researcher-env".path;
  };
  homeProfile = import ./hermes-profile.nix {
    profileName = "home";
    inherit config lib pkgs hermesPackage;
    configYaml = ./hermes-profiles/home/config.yaml;
    soulMd = ./hermes-profiles/home/SOUL.md;
    envSecretPath = config.sops.secrets."hermes-home-env".path;
  };
in
{
  sops.secrets."hermes/env" = {
    owner = "hermes";
    group = "hermes";
  };

  # --- Secondary profile secrets -----------------------------------------
  sops.secrets."hermes-coder-env" = {
    owner = "hermes";
    group = "hermes";
  };
  sops.secrets."hermes-researcher-env" = {
    owner = "hermes";
    group = "hermes";
  };
  sops.secrets."hermes-home-env" = {
    owner = "hermes";
    group = "hermes";
  };

  services.hermes-agent = {
    enable = true;
    container.enable = false;
    addToSystemPackages = true;

    settings = {
      model = {
        provider = "custom";
        base_url = "http://10.40.40.106:11434/v1";
        default = "qwen3:8b-q4_K_M";
        context_length = 65536;
        ollama_num_ctx = 65536;
      };

      fallback_providers = [
        {
          provider = "anthropic";
          model = "claude-sonnet-4-6";
        }
      ];

      delegation = {
        model = "qwen2.5:1.5b-instruct-q4_K_M";
        provider = "custom";
        base_url = "http://10.40.40.104:11434/v1";
        max_iterations = 10;
      };

      auxiliary = {
        title_generation = {
          provider = "custom";
          base_url = "http://10.40.40.104:11434/v1";
          model = "qwen2.5:3b-instruct-q4_K_M";
        };
        approval = {
          provider = "custom";
          base_url = "http://10.40.40.104:11434/v1";
          model = "qwen2.5:3b-instruct-q4_K_M";
        };
        triage_specifier = {
          provider = "custom";
          base_url = "http://10.40.40.104:11434/v1";
          model = "qwen2.5:3b-instruct-q4_K_M";
        };
        compression = {
          provider = "custom";
          base_url = "http://10.40.40.101:11434/v1";
          model = "phi4-mini:3.8b-q4_K_M";
          fallback_chain = [
            {
              provider = "custom";
              base_url = "http://10.40.40.104:11434/v1";
              model = "qwen2.5:3b-instruct-q4_K_M";
            }
          ];
        };
        skills_hub = {
          provider = "custom";
          base_url = "http://10.40.40.101:11434/v1";
          model = "phi4-mini:3.8b-q4_K_M";
        };
        mcp = {
          provider = "custom";
          base_url = "http://10.40.40.101:11434/v1";
          model = "phi4-mini:3.8b-q4_K_M";
        };
      };

      toolsets = [ "all" "kanban" ];

      compression = {
        enabled = true;
        threshold = 0.5;
      };

      kanban = {
        orchestrator_profile = "default";
        default_assignee = "researcher";
        auto_decompose = true;
        auto_decompose_per_tick = 3;
        auto_promote_children = true;
        failure_limit = 5;
        dispatch_in_gateway = true;
        dispatch_interval_seconds = 60;
      };

      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };

      gateway = {
        # CONFIRMED dead code on v0.17.0 (June 29 investigation) — left
        # explicitly false rather than removed, so a future reader sees
        # this was deliberately turned off, not merely never configured.
        # See the long comment at the top of this file for the full
        # investigation trail before ever flipping this back to true.
        multiplex_profiles = false;
        platforms = {
          telegram = {
            home_chat_id = "REPLACE_WITH_YOUR_TELEGRAM_USER_ID";
          };
	 discord = {
  	allowed_channels = [ "1521123068557131830" ];
  	free_response_channels = [ "1521123068557131830" ];
	home_chat_id = "1521123068557131830";
	 };
         };
        };
      };
    };


    environmentFiles = [ config.sops.secrets."hermes/env".path ];
    extraDependencyGroups = [ "messaging" "firecrawl" ];
  };

  # --- Secondary profiles: each a real systemd service ---------------
  # hermes-profile.nix returns a full module-shaped attrset per profile
  # (tmpfiles rules, an activationScript, AND a systemd.services entry this
  # time). Same manual-merge correctness note as before applies: these are
  # plain function calls, not `imports`, so system.activationScripts and
  # systemd.tmpfiles.rules are each assigned EXACTLY ONCE below, merged by
  # hand with `//`/`++` — NOT lib.mkMerge.
  #
  # CORRECTNESS FIX (caught via real dry-build error, not just reasoning):
  # an earlier draft had `systemd.services.hermes-agent.serviceConfig.
  # TimeoutStopSec = lib.mkForce "210s";` as ONE definition, and then
  # `systemd.services = coderProfile... // ...;` as a SEPARATE definition
  # further down — two assignments of the same top-level `systemd.services`
  # option in one plain attrset, which is a hard Nix error ("attribute
  # 'systemd.services' already defined"), not something the module system
  # auto-merges in this context. Fixed by folding hermes-agent's own
  # TimeoutStopSec override into the SAME single merged attrset as the
  # three profiles below, via `lib.recursiveUpdate`, which correctly
  # combines hermes-agent's nested serviceConfig with the three profiles'
  # entirely separate top-level keys (hermes-coder, hermes-researcher,
  # hermes-home) in one pass.
  systemd.tmpfiles.rules =
    coderProfile.systemd.tmpfiles.rules
    ++ researcherProfile.systemd.tmpfiles.rules
    ++ homeProfile.systemd.tmpfiles.rules;

  systemd.services = lib.recursiveUpdate
    (coderProfile.systemd.services
      // researcherProfile.systemd.services
      // homeProfile.systemd.services)
    {
      hermes-agent.serviceConfig.TimeoutStopSec = lib.mkForce "210s";
    };
  # OPEN QUESTION, flagged rather than assumed away: lib.mkForce produces an
  # internal marker that the MODULE SYSTEM's option-merging machinery is
  # meant to resolve (it's how one module's definition can override another
  # module's definition of the same option, with priority). The real
  # `services.hermes-agent` module sets its own `systemd.services.
  # hermes-agent` entry through normal `imports`-based module merging — but
  # THIS file's override reaches the same path through a plain
  # `lib.recursiveUpdate` on an ordinary attrset, outside that machinery.
  # It's possible mkForce's marker is simply left unresolved here and
  # TimeoutStopSec silently doesn't apply, rather than erroring. If dry-build
  # passes but `systemctl show hermes-agent.service -p TimeoutStopSec` after
  # a real switch doesn't show 210s (or whatever 1801-or-so default
  # systemd/the module otherwise uses), that's this exact uncertainty
  # manifesting — fix would be dropping mkForce here and using a plain
  # value instead, since recursiveUpdate's last-value-wins behavior may
  # already achieve the override without needing mkForce's priority marker
  # at all in this non-module context.

  system.activationScripts = {
    hermesSoul = {
      text = ''
        mkdir -p /var/lib/hermes/.hermes
        cp ${./SOUL.md} /var/lib/hermes/.hermes/SOUL.md
        chown hermes:hermes /var/lib/hermes/.hermes/SOUL.md
        chmod 660 /var/lib/hermes/.hermes/SOUL.md
      '';
      deps = [ "users" "groups" ];
    };
  } // coderProfile.system.activationScripts
    // researcherProfile.system.activationScripts
    // homeProfile.system.activationScripts;

  # users.users.xeseuses.extraGroups = [ "hermes" ];  # add to existing list if needed
}


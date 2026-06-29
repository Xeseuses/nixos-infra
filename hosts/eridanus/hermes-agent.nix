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
# SECONDARY PROFILES (coder, researcher, home) — added [this session].
# These are NOT separate gateway processes or systemd services. Corvus's
# gateway.multiplex_profiles = true (already set below, unchanged) means
# THIS service is the sole inbound process for every profile on the host.
# Adding coder/researcher/home only requires their config.yaml/SOUL.md/.env
# to exist under ~/.hermes/profiles/<name>/ before this service (re)starts
# — hermes-profile-files.nix handles exactly that, nothing more. See that
# file's header comment for why an earlier draft (a separate systemd unit
# per profile) was wrong for this host.
#
# Each secondary profile needs its OWN sops secret for .env — per Hermes'
# multi-profile-gateways docs, reusing a bot token across profiles is a
# hard error at gateway startup ("token-conflict safety"), so do NOT point
# more than one profile's environmentFile-equivalent at the same secret.
#
# secrets/secrets.yaml additionally needs, alongside the existing `hermes:`
# key (these are new, separate top-level keys — NOT nested under `hermes:`,
# to keep each profile's secret independently rotatable/revokable):
#   hermes-coder-env: |
#       DEEPSEEK_API_KEY=...
#   hermes-researcher-env: |
#       DEEPSEEK_API_KEY=...
#   hermes-home-env: |
#       # home's model (andromeda Ollama) needs no API key at all — this
#       # file can be empty, or can carry HASS_TOKEN/HASS_URL if home ever
#       # needs its own HA credential separate from Corvus's. Confirm
#       # whether Hermes errors on a profile .env that's entirely empty
#       # before assuming an empty file is safe — not yet verified.

{ config, lib, pkgs, ... }:

let
  coderFiles = import ./hermes-profile-files.nix {
    profileName = "coder";
    inherit config lib;
    configYaml = ./hermes-profiles/coder/config.yaml;
    soulMd = ./hermes-profiles/coder/SOUL.md;
    envSecretPath = config.sops.secrets."hermes-coder-env".path;
  };
  researcherFiles = import ./hermes-profile-files.nix {
    profileName = "researcher";
    inherit config lib;
    configYaml = ./hermes-profiles/researcher/config.yaml;
    soulMd = ./hermes-profiles/researcher/SOUL.md;
    envSecretPath = config.sops.secrets."hermes-researcher-env".path;
  };
  homeFiles = import ./hermes-profile-files.nix {
    profileName = "home";
    inherit config lib;
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

      toolsets = [ "all" ];

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
        multiplex_profiles = true;
        platforms = {
          telegram = {
            home_chat_id = "REPLACE_WITH_YOUR_TELEGRAM_USER_ID";
          };
          discord = {
            allowed_channels = "1521123260899791012";
            home_chat_id = "1521123260899791012";
          };
        };
      };
    };

    environmentFiles = [ config.sops.secrets."hermes/env".path ];
    extraDependencyGroups = [ "messaging" ];
  };

  systemd.services.hermes-agent.serviceConfig.TimeoutStopSec = lib.mkForce "210s";

  # --- Secondary profiles: render config.yaml/SOUL.md/.env into place ----
  # These are NOT separate gateway processes or systemd services. Corvus's
  # gateway.multiplex_profiles = true (set above, unchanged) means THIS
  # service is the sole inbound process for every profile on the host.
  # Adding coder/researcher/home only requires their config.yaml/SOUL.md/
  # .env to exist under ~/.hermes/profiles/<name>/ before this service
  # (re)starts — hermes-profile-files.nix handles exactly that, nothing
  # more. See that file's header comment for why an earlier draft (a
  # separate systemd unit per profile) was wrong for this host.
  #
  # CORRECTNESS NOTE on this merge: hermes-profile-files.nix is called as a
  # plain function (not via `imports`), so its return value is an ordinary
  # Nix attrset, not a NixOS module — none of the module system's automatic
  # option-merging applies here. Below, system.activationScripts and
  # systemd.tmpfiles.rules are each assigned EXACTLY ONCE in this file's
  # returned attrset, with Corvus's own hermesSoul script and tmpfiles
  # rules (if any) merged in by hand using plain `//` (attrset merge) and
  # `++` (list concat) — NOT lib.mkMerge, which is a module-system
  # primitive for combining option *definitions* across separate module
  # files, not a general-purpose merge helper for plain values computed
  # inside one module's body. Using mkMerge here would have been wrong.
  #
  # This has been reasoned through carefully but NOT validated with a real
  # `nixos-rebuild dry-build` against the actual flake/secrets — treat as
  # "should be correct Nix" until confirmed, not as already-proven.
  systemd.tmpfiles.rules =
    coderFiles.systemd.tmpfiles.rules
    ++ researcherFiles.systemd.tmpfiles.rules
    ++ homeFiles.systemd.tmpfiles.rules;

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
  } // coderFiles.system.activationScripts
    // researcherFiles.system.activationScripts
    // homeFiles.system.activationScripts;

  # users.users.xeseuses.extraGroups = [ "hermes" ];  # add to existing list if needed
}


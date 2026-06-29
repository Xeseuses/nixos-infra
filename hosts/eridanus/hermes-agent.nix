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

{ config, lib, pkgs, ... }:

{
  sops.secrets."hermes/env" = {
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

  system.activationScripts.hermesSoul = {
    text = ''
      mkdir -p /var/lib/hermes/.hermes
      cp ${./SOUL.md} /var/lib/hermes/.hermes/SOUL.md
      chown hermes:hermes /var/lib/hermes/.hermes/SOUL.md
      chmod 660 /var/lib/hermes/.hermes/SOUL.md
    '';
    deps = [ "users" "groups" ];
  };

  # users.users.xeseuses.extraGroups = [ "hermes" ];  # add to existing list if needed
}


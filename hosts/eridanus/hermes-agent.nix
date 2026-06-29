# Hermes Agent orchestrator — runs on eridanus alongside Nextcloud/binary-cache/
# security-dashboard. This host runs no LLM inference itself; it's the
# control-plane process that calls out to horologium (primary), andromeda +
# caelum (auxiliary tasks), andromeda again (HA-delegation fast path), and
# Anthropic (emergency fallback only).
#
# Requires: inputs.hermes-agent.nixosModules.default added to eridanus's
# module list in flake.nix.
#
# Requires: secrets/secrets.yaml (repo root) to contain, nested under a
# `hermes:` key (NOT a flat "hermes/env" key — see note at bottom):
#   hermes:
#       env: |
#           ANTHROPIC_API_KEY=sk-ant-...
#           TELEGRAM_BOT_TOKEN=...
#           TELEGRAM_ALLOWED_USERS=<your numeric telegram id>
#           HASS_TOKEN=<long-lived access token from HA>
#           HASS_URL=http://10.40.40.115:8123

{ config, lib, pkgs, ... }:

{
  sops.secrets."hermes/env" = {
    owner = "hermes";
    group = "hermes";
  };

  services.hermes-agent = {
    enable = true;
    container.enable = false; # native systemd mode — gets hardened sandboxing for free
    addToSystemPackages = true;

    settings = {
      # ── Primary model: horologium's RTX 3060 via Ollama's OpenAI-compatible API ──
      model = {
        provider = "custom"; # MANDATORY — omitting this causes Hermes to
                              # misdetect the model string as Anthropic's
                              # and crash trying to import the anthropic package
        base_url = "http://10.40.40.106:11434/v1";
        default = "qwen3:8b-q4_K_M";
        # Both lines below are required TOGETHER. context_length satisfies
        # Hermes' own pre-flight check on the model's declared capability.
        # ollama_num_ctx is the separate, also-required instruction telling
        # Ollama what to actually load the model with at runtime. Setting
        # only one produces two different failure modes at two different
        # stages — this was a real, two-step debugging process tonight.
        context_length = 65536;
        ollama_num_ctx = 65536;
      };

      # ── Fallback: Claude, only on primary-model failure, turn-scoped ──
      fallback_providers = [
        {
          provider = "anthropic";
          model = "claude-sonnet-4-6";
        }
      ];

      # ── Delegation: the fast path for HA-related delegate_task calls ──
      # This is a GLOBAL setting — every delegate_task call uses this model
      # unless Hermes ships per-task overrides in the future (not yet
      # shipped as of tonight; tracked across several open upstream issues).
      # SOUL.md below instructs Corvus to only delegate HA-type work this
      # way, since this is the only delegation target configured.
      delegation = {
        model = "qwen2.5:1.5b-instruct-q4_K_M";
        provider = "custom";
        base_url = "http://10.40.40.104:11434/v1"; # andromeda
        max_iterations = 10; # HA actions are simple, don't need 50 turns
      };

      # ── Auxiliary tasks split across the two Beelink tiers ──
      auxiliary = {
        title_generation = {
          provider = "custom";
          base_url = "http://10.40.40.104:11434/v1"; # andromeda
          model = "qwen2.5:3b-instruct-q4_K_M";
        };
        approval = {
          provider = "custom";
          base_url = "http://10.40.40.104:11434/v1"; # andromeda
          model = "qwen2.5:3b-instruct-q4_K_M";
        };
        triage_specifier = {
          provider = "custom";
          base_url = "http://10.40.40.104:11434/v1"; # andromeda
          model = "qwen2.5:3b-instruct-q4_K_M";
        };

        compression = {
          provider = "custom";
          base_url = "http://10.40.40.101:11434/v1"; # caelum
          model = "phi4-mini:3.8b-q4_K_M";
          fallback_chain = [
            {
              provider = "custom";
              base_url = "http://10.40.40.104:11434/v1"; # andromeda, if caelum's down
              model = "qwen2.5:3b-instruct-q4_K_M";
            }
          ];
        };
        skills_hub = {
          provider = "custom";
          base_url = "http://10.40.40.101:11434/v1"; # caelum
          model = "phi4-mini:3.8b-q4_K_M";
        };
        mcp = {
          provider = "custom";
          base_url = "http://10.40.40.101:11434/v1"; # caelum
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

      # No gateway.platforms.homeassistant block needed — the four ha_*
      # tools (list_entities, get_state, list_services, call_service)
      # activate automatically the moment HASS_TOKEN is set in the env
      # file below. This block only matters if you later want PROACTIVE
      # state-change notifications, which was deliberately declined.
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

    environmentFiles = [ config.sops.secrets."hermes/env".path ];

    # Messaging dependency group — required for the Telegram client library
    # to actually be built into the package. Already enabled (was commented
    # out during initial setup, then turned on for the Telegram rollout).
    extraDependencyGroups = [ "messaging" ];
  };

  # Hermes' gateway has an internal drain_timeout of 180s, but the unit's
  # default TimeoutStopSec is shorter — systemd would kill the process
  # mid-drain. Match what the service itself warns it wants on startup.
  systemd.services.hermes-agent.serviceConfig.TimeoutStopSec = lib.mkForce "210s";

  # SOUL.md (Corvus's personality + delegation instructions) deployed
  # declaratively so a from-scratch host rebuild doesn't lose it. The file
  # lives at hosts/eridanus/SOUL.md, next to this module.
  system.activationScripts.hermesSoul = {
    text = ''
      mkdir -p /var/lib/hermes/.hermes
      cp ${./SOUL.md} /var/lib/hermes/.hermes/SOUL.md
      chown hermes:hermes /var/lib/hermes/.hermes/SOUL.md
      chmod 660 /var/lib/hermes/.hermes/SOUL.md
    '';
    deps = [ "users" "groups" ];
  };

  # If you ever add yourself to the hermes group for `hermes chat` access
  # over SSH (needed once, to read /var/lib/hermes/.hermes/.env — files
  # created by a USER session there get owned by that user, not "hermes",
  # which silently breaks the service's own ability to read them):
  # users.users.xeseuses.extraGroups = [ "hermes" ];  # add to existing list

  # eridanus is already on the Servers VLAN; Hermes needs outbound to
  # horologium/andromeda/caelum (all VLAN40, already permitted) and
  # outbound to api.anthropic.com for the fallback. No new firewall
  # opening needed on eridanus itself unless the messaging gateway needs
  # inbound (it doesn't — Telegram is long-polled outbound).
}

# NOTE on the SOPS secret structure: the repo's convention (confirmed via
# hosts/eridanus/default.nix's sops.defaultSopsFile) is ONE shared file at
# secrets/secrets.yaml with slash-namespaced keys written as REAL YAML
# NESTING — e.g.:
#   hermes:
#       env: |
#           KEY=value
# NOT a flat key literally named "hermes/env: |" — that's a different,
# incompatible shape even though both resolve to the same "hermes/env"
# string on the Nix side. This bit us once already (sops-install-secrets
# error: "key 'hermes' cannot be found").


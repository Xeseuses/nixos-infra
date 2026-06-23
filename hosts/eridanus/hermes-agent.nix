# Hermes Agent orchestrator — runs on eridanus alongside Nextcloud/binary-cache/
# security-dashboard. This host runs no LLM inference itself; it's the
# control-plane process that calls out to horologium (primary) and
# andromeda/caelum (auxiliary tasks) over the Servers VLAN.
#
# Requires: inputs.hermes-agent.nixosModules.default added to eridanus's
# module list in flake.nix (see flake-input-snippet.nix in this same dir).

{ config, lib, pkgs, ... }:

{
  # eridanus/default.nix already sets sops.defaultSopsFile to the shared
  # ../../secrets/secrets.yaml — this just adds a key inside it, matching
  # the namespaced-key convention used elsewhere (e.g. "lyra/wireguard/private-key").
  #
  # Add this to secrets/secrets.yaml first via `sops secrets/secrets.yaml`:
  #
  #   hermes/env: |
  #       ANTHROPIC_API_KEY=sk-ant-your-key-here
  #
  sops.secrets."hermes/env" = {
    # Match ownership to whatever user/group the hermes service runs as
    # (default "hermes"/"hermes" per the module's own defaults below).
    owner = "hermes";
    group = "hermes";
  };

  services.hermes-agent = {
    enable = true;

    # Native systemd mode, not container mode — no need for self-modifying
    # package installs here, and native mode gets the hardened systemd
    # sandboxing (NoNewPrivileges, ProtectSystem=strict, PrivateTmp) for
    # free. Matches the security posture of your other eridanus services.
    container.enable = false;

    addToSystemPackages = true; # lets you run `hermes chat` etc. interactively over SSH

    settings = {
      # ── Primary model: horologium's RTX 3060 via Ollama's OpenAI-compatible API ──
      model = {
        base_url = "http://10.40.40.106:11434/v1";
        default = "qwen2.5:14b-instruct-q4_K_M";
      };

      # ── Fallback: Claude, only on primary-model failure, turn-scoped ──
      fallback_providers = [
        {
          provider = "anthropic";
          model = "claude-sonnet-4-6";
        }
      ];

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
          model = "phi4-mini:q4_K_M";
          # Per-task fallback if caelum's instance is down: try andromeda's
          # model before falling all the way through to the main agent model.
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
          base_url = "http://10.40.40.101:11434/v1"; # caelum
          model = "phi4-mini:q4_K_M";
        };
        mcp = {
          provider = "custom";
          base_url = "http://10.40.40.101:11434/v1"; # caelum
          model = "phi4-mini:q4_K_M";
        };
      };

      toolsets = [ "all" ];
      compression = {
        enabled = true;
        threshold = 0.5; # matches the "compress at 50%" idea from the cost guide — genuinely useful regardless of model cost
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
    };

    environmentFiles = [ config.sops.secrets."hermes/env".path ];

    # Discord/Telegram/Slack support is opt-in at build time (Nix can't
    # install these at runtime). Uncomment when you're ready for Week 2
    # of the rollout (messaging gateway).
    # extraDependencyGroups = [ "messaging" ];
  };

  # eridanus is already on the Servers VLAN per your topology; Hermes only
  # needs outbound to horologium/andromeda/caelum (all VLAN40, already
  # permitted by your existing forward policy) and outbound to
  # api.anthropic.com for the fallback. No new firewall opening needed on
  # eridanus itself unless you later expose the messaging gateway.
}


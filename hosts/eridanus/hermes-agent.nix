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
        provider = "custom";
        base_url = "http://10.40.40.106:11434/v1";
        default = "qwen3:8b-q4_K_M";
        # Qwen3 8B has the same 32K-native/YaRN-to-128K context architecture
        # as Qwen2.5 14B (no architectural fix there), but its much smaller
        # weights (~4.5GB vs ~9GB at Q4) leave far more of the 12GB VRAM
        # budget free for the stretched 64K KV cache — this is what should
        # actually fix the CPU-offload problem we hit with the 14B model
        # (only 27/49 layers on GPU, ~1min/response). Verify after first
        # load: `journalctl -u ollama | grep offload` should show all
        # layers on GPU this time. Qwen3 8B-class models are specifically
        # well-evaluated for tool-calling reliability (BFCL V4, Docker's
        # agent-loop benchmark), which matters more for Hermes than raw
        # parameter count.
        context_length = 65536;
        ollama_num_ctx = 65536;
      };

      gateway = {
  	platforms = {
	    telegram = {
      	    home_chat_id = "2075931733";
          };
        };
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
    # install these at runtime).
    extraDependencyGroups = [ "messaging" ];
  };

  # eridanus is already on the Servers VLAN per your topology; Hermes only
  # needs outbound to horologium/andromeda/caelum (all VLAN40, already
  # permitted by your existing forward policy) and outbound to
  # api.anthropic.com for the fallback. No new firewall opening needed on
  # eridanus itself unless you later expose the messaging gateway.

  # Hermes' gateway has an internal drain_timeout of 180s (time it allows
  # in-flight work to finish before a forceful stop), but the unit's
  # default TimeoutStopSec is shorter — systemd would kill the process
  # mid-drain. Match what the service itself warns it wants on startup.
  systemd.services.hermes-agent.serviceConfig.TimeoutStopSec = lib.mkForce "210s";

  # SOUL.md (the agent's persona/identity file) is normally a hand-edited
  # file living outside Nix control — this makes it declarative instead,
  # so a from-scratch rebuild of eridanus doesn't lose the customization.
  # The actual prose lives in ./SOUL.md alongside this module; edit that
  # file and rebuild to change Corvus's personality.
  #
  # Runs after sops-install-secrets (which creates /var/lib/hermes) and
  # before the hermes-agent service starts, so ownership is correct from
  # the first write — no chown cleanup needed.
  system.activationScripts.hermesSoul = {
    text = ''
      mkdir -p /var/lib/hermes/.hermes
      cp ${./SOUL.md} /var/lib/hermes/.hermes/SOUL.md
      chown hermes:hermes /var/lib/hermes/.hermes/SOUL.md
      chmod 660 /var/lib/hermes/.hermes/SOUL.md
    '';
    deps = [ "users" "groups" ];
  };
}


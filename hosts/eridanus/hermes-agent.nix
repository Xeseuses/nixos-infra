{ config, lib, pkgs, ... }:

let
  corvusExecStart = config.systemd.services.hermes-agent.serviceConfig.ExecStart;
  hermesPackageRoot =
    let
      execStartStr =
        if builtins.isList corvusExecStart
        then builtins.head corvusExecStart
        else corvusExecStart;
      parts = lib.strings.splitString "/bin/hermes" execStartStr;
    in
    if builtins.length parts < 2
    then throw "hermes-agent.nix: could not find '/bin/hermes' in hermes-agent.service's ExecStart (${execStartStr})"
    else builtins.elemAt parts 0;
  hermesPackage = pkgs.runCommand "hermes-agent-package-ref" { } ''
    ln -s ${lib.escapeShellArg hermesPackageRoot} $out
  '';

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
  sops.secrets."hermes-dashboard-env" = {
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

    environmentFiles = [ config.sops.secrets."hermes/env".path ];
    extraDependencyGroups = [ "messaging" "firecrawl" ];
  };

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
      hermes-dashboard = {
        description = "Hermes Agent Web Dashboard";
        after = [ "hermes-agent.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          User = "hermes";
          Group = "hermes";
          EnvironmentFile = config.sops.secrets."hermes-dashboard-env".path;
          ExecStart = "${hermesPackage}/bin/hermes dashboard --no-open --host 10.40.40.117 --port 9119 --insecure --allowed-hosts hermes.lan";
          Restart = "on-failure";
          RestartSec = 10;
        };
      };
    };

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


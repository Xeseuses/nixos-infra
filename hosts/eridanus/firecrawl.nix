{ config, lib, pkgs, ... }:

let
  cfg = config.services.firecrawl-api;
  inherit (lib) mkEnableOption mkOption mkIf types;

  firecrawlSrc = pkgs.fetchFromGitHub {
    owner = "mendableai";
    repo = "firecrawl";
    rev = cfg.rev;
    sha256 = cfg.sha256;
  };

  firecrawlApi = pkgs.buildNpmPackage {
    name = "firecrawl-api";
    src = "${firecrawlSrc}/apps/api";

    npmDepsHash = cfg.npmDepsHash;

    nativeBuildInputs = with pkgs; [ python3 pkg-config ];
    buildInputs = with pkgs; [ nodejs_22 go ];

    preBuild = ''
      pushd sharedLibs/go-html-to-md
      go build -o html-to-md .
      popd
    '';

    buildPhase = ''
      runHook preBuild
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      mkdir -p $out/lib/firecrawl
      cp -r dist/ $out/lib/firecrawl/dist
      cp -r node_modules/ $out/lib/firecrawl/node_modules
      cp -r sharedLibs/ $out/lib/firecrawl/sharedLibs
      cp package.json $out/lib/firecrawl/
    '';
  };

in
{
  options.services.firecrawl-api = {
    enable = mkEnableOption "Firecrawl scraping API server";

    port = mkOption {
      type = types.port;
      default = 3002;
      description = "Port the Firecrawl API listens on.";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host address to bind to.";
    };

    rev = mkOption {
      type = types.str;
      default = "v1.9.0";
      description = "GitHub revision (tag or commit) of firecrawl to build.";
    };

    sha256 = mkOption {
      type = types.nonEmptyStr;
      default = "sha256-LYkOOWSDI12YiOLfJXwoxt871jhPv8GgSe6HmfuprK8=";
      description = "SHA-256 hash of the firecrawl source. Set lib.fakeSha256 for first build, then replace with actual hash.";
    };

    npmDepsHash = mkOption {
      type = types.nonEmptyStr;
      default = "sha256-LYkOOWSDI12YiOLfJXwoxt871jhPv8GgSe6HmfuprK8=";
      description = "SHA-256 hash of npm dependencies. Set lib.fakeSha256 for first build, then replace with actual hash.";
    };

    redisUrl = mkOption {
      type = types.str;
      default = "redis://127.0.0.1:***@127.0.0.1:6379/firecrawl";
      description = "Redis connection string for Firecrawl.";
    };

    databaseUrl = mkOption {
      type = types.str;
      default = "postgresql://firecrawl:firrcrawl_secret@127.0.0.1:5433/firecrawl";
      description = "PostgreSQL connection string for Firecrawl.";
    };

    apiKey = mkOption {
      type = types.str;
      default = "";
      description = "Optional API key for authentication. Leave empty to disable auth.";
    };

    bullAuthKey = mkOption {
      type = types.str;
      default = "changeme";
      description = "Auth key for the Bull Queue admin UI at /admin/<key>/queues.";
    };

    user = mkOption {
      type = types.str;
      default = "firecrawl";
      description = "System user to run the Firecrawl services.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      createHome = false;
    };
    users.groups.${cfg.user} = {};

    environment.etc."firecrawl/env".text = ''
      PORT=${toString cfg.port}
      HOST=${cfg.host}
      USE_DB_AUTHENTICATION=false
      REDIS_URL=${cfg.redisUrl}
      REDIS_RATE_LIMIT_URL=${cfg.redisUrl}
      DATABASE_URL=${cfg.databaseUrl}
      BULL_AUTH_KEY=${cfg.bullAuthKey}
      NUM_WORKERS=2
      ${lib.optionalString (cfg.apiKey != "") "API_KEY=${cfg.apiKey}"}
    '';

    systemd.services.firecrawl-api-server = {
      description = "Firecrawl Scraping API Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "firecrawl-postgres.service" ];
      requires = [ "firecrawl-postgres.service" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.user;
        EnvironmentFile = "/etc/firecrawl/env";
        WorkingDirectory = "${firecrawlApi}/lib/firecrawl";
        ExecStart = "${pkgs.nodejs_22}/bin/node dist/src/index.js";
        Restart = "on-failure";
        RestartSec = "5";
        TimeoutStopSec = "30";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/tmp" ];
      };
    };

    systemd.services.firecrawl-api-worker = {
      description = "Firecrawl Queue Worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "firecrawl-postgres.service" ];
      requires = [ "firecrawl-postgres.service" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.user;
        EnvironmentFile = "/etc/firecrawl/env";
        WorkingDirectory = "${firecrawlApi}/lib/firecrawl";
        ExecStart = "${pkgs.nodejs_22}/bin/node dist/src/services/queue-worker.js";
        Restart = "on-failure";
        RestartSec = "5";
        TimeoutStopSec = "30";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/tmp" ];
      };
    };
  };
}

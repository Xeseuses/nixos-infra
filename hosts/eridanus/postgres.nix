{ config, lib, pkgs, ... }:

let
  cfg = config.services.firecrawl-postgres;
  inherit (lib) mkEnableOption mkOption mkIf types;
in
{
  options.services.firecrawl-postgres = {
    enable = mkEnableOption "Firecrawl-specific PostgreSQL instance";

    port = mkOption {
      type = types.port;
      default = 5433;
      description = "Port this PostgreSQL instance listens on. Offsets from 5432 to avoid conflicting with a system PostgreSQL.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/firecrawl/postgres";
      description = "Data directory for the Firecrawl PostgreSQL instance.";
    };

    database = mkOption {
      type = types.str;
      default = "firecrawl";
      description = "Default database name.";
    };

    user = mkOption {
      type = types.str;
      default = "firecrawl";
      description = "PostgreSQL user for Firecrawl.";
    };

    password = mkOption {
      type = types.str;
      default = "firecrawl";
      description = "Password for the PostgreSQL user. Change in production.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.firecrawl-postgres = {
      description = "Firecrawl PostgreSQL Database";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      preStart = ''
        if ! test -d '${cfg.dataDir}'; then
          mkdir -p '${cfg.dataDir}'
          ${pkgs.postgresql_16}/bin/initdb -D '${cfg.dataDir}' --auth=trust --username=${cfg.user}
          # Configure port per option
          echo "port = ${toString cfg.port}" >> '${cfg.dataDir}/postgresql.conf'
          echo "listen_addresses = 'localhost'" >> '${cfg.dataDir}/postgresql.conf'
          echo "unix_socket_directories = '${cfg.dataDir}/run'" >> '${cfg.dataDir}/postgresql.conf'
        fi
      '';

      serviceConfig = {
        Type = "forking";
        User = "postgres";
        Group = "postgres";
        UMask = "0077";
        ExecStart = "${pkgs.postgresql_16}/bin/pg_ctl start -D '${cfg.dataDir}' -l '${cfg.dataDir}/pg.log' -o \"-p ${toString cfg.port}\"";
        ExecStop = "${pkgs.postgresql_16}/bin/pg_ctl stop -D '${cfg.dataDir}' -m fast";
        ExecReload = "${pkgs.postgresql_16}/bin/pg_ctl reload -D '${cfg.dataDir}'";
        Restart = "on-failure";
        RestartSec = "5";
        TimeoutStartSec = "60";
        TimeoutStopSec = "60";
      };
    };

    # Create the database and user after first start
    systemd.services.firecrawl-postgres-init = {
      description = "Initialize Firecrawl PostgreSQL database and user";
      wantedBy = [ "multi-user.target" ];
      after = [ "firecrawl-postgres.service" ];
      requires = [ "firecrawl-postgres.service" ];

      script = ''
        export PGPASSWORD=${toString cfg.password}
        ${pkgs.postgresql_16}/bin/psql -h 127.0.0.1 -p ${toString cfg.port} -U ${cfg.user} -d postgres -tc \
          "SELECT 1 FROM pg_database WHERE datname = '${cfg.database}'" | grep -q 1 || \
          ${pkgs.postgresql_16}/bin/createdb -h 127.0.0.1 -p ${toString cfg.port} -U ${cfg.user} '${cfg.database}'
        ${pkgs.postgresql_16}/bin/psql -h 127.0.0.1 -p ${toString cfg.port} -U ${cfg.user} -d ${cfg.database} -c \
          "GRANT ALL PRIVILEGES ON DATABASE ${cfg.database} TO ${cfg.user};"
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        RemainAfterExit = true;
      };
    };

    users.users.postgres = {
      isSystemUser = true;
      group = "postgres";
      createHome = false;
    };
    users.groups.postgres = {};
  };
}

{ config, lib, pkgs, ... }:

let
  cfg = config.services.firecrawl-redis;
  inherit (lib) mkEnableOption mkOption mkIf types;
in
{
  options.services.firecrawl-redis = {
    enable = mkEnableOption "Redis for Firecrawl self-hosted scraping service";

    port = mkOption {
      type = types.port;
      default = 6379;
      description = "Port Redis listens on.";
    };
  };

  config = mkIf cfg.enable {
    services.redis.servers.firecrawl = {
      enable = true;
      port = cfg.port;
      bind = "127.0.0.1";
      settings = {
        save = [ "900 1" "300 10" "60 10000" ];
      };
    };
  };
}

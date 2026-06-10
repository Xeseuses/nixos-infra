# hosts/eridanus/nextcloud.nix
#
# Nextcloud on eridanus — file sync, calendar, contacts.
# PostgreSQL as database (local, dedicated to Nextcloud).
# Accessible externally via cloud.xesh.cc through lyra Caddy.
{ config, pkgs, ... }:
{
  # ── SOPS secrets ──────────────────────────────────────────────────────────
  sops.secrets."eridanus/nextcloud/admin-password" = {
    owner = "nextcloud";
  };
  sops.secrets."eridanus/nextcloud/db-password" = {
    owner = "nextcloud";
  };

  # ── PostgreSQL ────────────────────────────────────────────────────────────
  services.postgresql = {
    enable      = true;
    package     = pkgs.postgresql_16;
    ensureDatabases = [ "nextcloud" ];
    ensureUsers = [{
      name              = "nextcloud";
      ensureDBOwnership = true;
    }];
  };

  # ── Nextcloud ─────────────────────────────────────────────────────────────
  services.nextcloud = {
    enable   = true;
    package  = pkgs.nextcloud33;
    hostName = "cloud.xesh.cc";
    https    = true;

    # Data directory — under /var/lib/nextcloud which is persisted below
    datadir = "/var/lib/nextcloud";

    # Database
    database.createLocally = false;
    config = {
      dbtype     = "pgsql";
      dbname     = "nextcloud";
      dbuser     = "nextcloud";
      dbhost     = "/run/postgresql";   # Unix socket — no password needed
      adminpassFile = config.sops.secrets."eridanus/nextcloud/admin-password".path;
      adminuser     = "admin";
    };

    # Settings
    settings = {
      # Trusted domains — internal + external
      trusted_domains = [
        "cloud.xesh.cc"
        "cloud.lan"
        "10.40.40.117"
        "10.200.0.0/24"   # WireGuard clients
      ];
      trusted_proxies    = [ "10.200.0.1" ];   # lyra WireGuard IP
      overwriteprotocol  = "https";
      default_phone_region = "NL";
      default_locale       = "nl_NL";

      # Performance
      "memcache.local"      = "\\OC\\Memcache\\APCu";
          };

    # PHP settings
    phpOptions = {
      "opcache.memory_consumption"         = "256";
      "opcache.interned_strings_buffer"    = "64";
      "opcache.max_accelerated_files"      = "20000";
      "opcache.revalidate_freq"            = "1";
      "opcache.save_comments"              = "1";
    };

    # Auto-update apps
    autoUpdateApps.enable  = true;
    autoUpdateApps.startAt = "04:30";

    # Built-in apps to enable
    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        calendar
        contacts
        tasks
        notes;
    };
    extraAppsEnable = true;
  };

  # ── Redis (for Nextcloud caching + locking) ───────────────────────────────
  services.nextcloud.configureRedis = true;

  # ── nginx (Nextcloud NixOS module requires nginx) ─────────────────────────
  # The Nextcloud module manages its own nginx vhost.
  # We expose it on port 80 internally — lyra Caddy handles TLS externally.
  services.nginx = {
    enable = true;
    recommendedGzipSettings  = true;
    recommendedOptimisation   = true;
    recommendedProxySettings  = true;
    recommendedTlsSettings    = false;   # TLS handled by lyra
  };

  # ── Firewall ──────────────────────────────────────────────────────────────
  # Port 80 — nginx serving Nextcloud, accessed via lyra reverse proxy
  # Only allow from WireGuard tunnel (lyra proxies through wg0)
  networking.firewall.interfaces.wg0.allowedTCPPorts = [ 80 443 ];
  # Also allow from local VLAN40 for direct internal access
  networking.firewall.interfaces.enp1s0.allowedTCPPorts = [ 80 ];

  systemd.tmpfiles.rules = [
  "d /var/lib/nextcloud/config     0750 nextcloud nextcloud -"
  "d /var/lib/nextcloud/data       0750 nextcloud nextcloud -"
  "d /var/lib/nextcloud/store-apps 0750 nextcloud nextcloud -"
  "d /var/lib/nextcloud/apps       0750 nextcloud nextcloud -"
];

  # ── Impermanence ──────────────────────────────────────────────────────────
  environment.persistence."/persist".directories = [
    "/var/lib/nextcloud"       # all Nextcloud data + config
    "/var/lib/postgresql"      # PostgreSQL database
    "/var/lib/redis-nextcloud" # Redis data
  ];
}


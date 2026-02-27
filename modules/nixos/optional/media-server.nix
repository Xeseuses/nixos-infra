{ config, pkgs, lib, ... }:
{
  # === Docker ===
  virtualisation.docker = {
    enable           = true;
    enableOnBoot     = true;
    autoPrune.enable = true;
  };

  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers = {

    # ── Jellyfin ──────────────────────────────────────────────────────────────
    jellyfin = {
      image   = "jellyfin/jellyfin:latest";
      volumes = [
        "/var/lib/jellyfin/config:/config"
        "/var/lib/jellyfin/cache:/cache"
        "/media:/media:ro"
        "/dev/dri:/dev/dri"
      ];
      environment = {
        JELLYFIN_PublishedServerUrl = "http://horologium.lan:8096";
      };
      extraOptions = [
        "--device=/dev/dri/renderD128"
        "--group-add=video"
        "--network=host"
      ];
      autoStart = true;
    };

    # ── Prowlarr (indexer manager) ─────────────────────────────────────────────
    prowlarr = {
      image   = "lscr.io/linuxserver/prowlarr:latest";
      volumes = [ "/var/lib/prowlarr:/config" ];
      ports   = [ "9696:9696" ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };
      autoStart = true;
    };

    # ── Sonarr (TV shows) ──────────────────────────────────────────────────────
    sonarr = {
      image   = "lscr.io/linuxserver/sonarr:latest";
      volumes = [
        "/var/lib/sonarr:/config"
        "/media:/media"
      ];
      ports   = [ "8989:8989" ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };
      autoStart = true;
    };

    # ── Radarr (movies) ────────────────────────────────────────────────────────
    radarr = {
      image   = "lscr.io/linuxserver/radarr:latest";
      volumes = [
        "/var/lib/radarr:/config"
        "/media:/media"
      ];
      ports   = [ "7878:7878" ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };
      autoStart = true;
    };

    # ── Bazarr (subtitles) ─────────────────────────────────────────────────────
    bazarr = {
      image   = "lscr.io/linuxserver/bazarr:latest";
      volumes = [
        "/var/lib/bazarr:/config"
        "/media:/media"
      ];
      ports   = [ "6767:6767" ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };
      autoStart = true;
    };

    # ── SABnzbd (usenet download client) ──────────────────────────────────────
    sabnzbd = {
      image   = "lscr.io/linuxserver/sabnzbd:latest";
      volumes = [
        "/var/lib/sabnzbd:/config"
        "/media/downloads:/media/downloads"
      ];
      ports   = [ "8080:8080" ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
        HOST_WHITELIST_ENTRIES = "horologium.lan,10.40.40.106";
      };
      autoStart = true;
    };

  };

  # Persistent data directories
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin/config 0755 root root -"
    "d /var/lib/jellyfin/cache  0755 root root -"
    "d /var/lib/prowlarr         0755 root root -"
    "d /var/lib/sonarr           0755 root root -"
    "d /var/lib/radarr           0755 root root -"
    "d /var/lib/bazarr           0755 root root -"
    "d /var/lib/sabnzbd          0755 root root -"
  ];
}


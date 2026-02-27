{ config, pkgs, lib, ... }:

{
  ########################################
  # Docker
  ########################################

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };

  virtualisation.oci-containers.backend = "docker";

  ########################################
  # Media User
  ########################################

  users.groups.media = {};
  users.users.media = {
    isSystemUser = true;
    group = "media";
    uid = 1000;
  };

  ########################################
  # Containers
  ########################################

  virtualisation.oci-containers.containers = {

    ########################################
    # Jellyfin
    ########################################
    jellyfin = {
      image = "jellyfin/jellyfin:latest";

      volumes = [
        "/var/lib/jellyfin/config:/config"
        "/var/lib/jellyfin/cache:/cache"
        "/media:/media"
        "/dev/dri:/dev/dri"
      ];

      environment = {
        JELLYFIN_PublishedServerUrl = "http://horologium.lan:8096";
      };

      extraOptions = [
        "--network=host"
        "--group-add=video"
        "--device=/dev/dri/renderD128"
      ];

      autoStart = true;
    };

    ########################################
    # SABnzbd
    ########################################
    sabnzbd = {
      image = "lscr.io/linuxserver/sabnzbd:latest";

      volumes = [
        "/var/lib/sabnzbd:/config"
        "/media:/media"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };

      extraOptions = [ "--network=host" ];

      autoStart = true;
    };

    ########################################
    # Sonarr
    ########################################
    sonarr = {
      image = "lscr.io/linuxserver/sonarr:latest";

      volumes = [
        "/var/lib/sonarr:/config"
        "/media:/media"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };

      extraOptions = [ "--network=host" ];

      autoStart = true;
    };

    ########################################
    # Radarr
    ########################################
    radarr = {
      image = "lscr.io/linuxserver/radarr:latest";

      volumes = [
        "/var/lib/radarr:/config"
        "/media:/media"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };

      extraOptions = [ "--network=host" ];

      autoStart = true;
    };

    ########################################
    # Prowlarr
    ########################################
    prowlarr = {
      image = "lscr.io/linuxserver/prowlarr:latest";

      volumes = [
        "/var/lib/prowlarr:/config"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };

      extraOptions = [ "--network=host" ];

      autoStart = true;
    };

    ########################################
    # Bazarr
    ########################################
    bazarr = {
      image = "lscr.io/linuxserver/bazarr:latest";

      volumes = [
        "/var/lib/bazarr:/config"
        "/media:/media"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ   = "Europe/Amsterdam";
      };

      extraOptions = [ "--network=host" ];

      autoStart = true;
    };
  };

  ########################################
  # Persistent Directories
  ########################################

  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin/config 0755 media media -"
    "d /var/lib/jellyfin/cache  0755 media media -"
    "d /var/lib/sabnzbd          0755 media media -"
    "d /var/lib/sonarr           0755 media media -"
    "d /var/lib/radarr           0755 media media -"
    "d /var/lib/prowlarr         0755 media media -"
    "d /var/lib/bazarr           0755 media media -"
  ];
}

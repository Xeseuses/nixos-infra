{ config, pkgs, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  # === SOPS Configuration ===
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets = {
      "users/xeseuses/hashedPassword" = {
        neededForUsers = true;
      };
    };
  };

  # === Custom Options ===
  asthrossystems = {
    hostInfo = "Custom Build, i5-13500, 16GB RAM, 476GB NVMe + 4x1.8TB ZFS";
    isServer = true;
    features = {
      impermanence = false;
      secureBoot   = false;
      encryption   = false;
    };
    storage = {
      rootDisk   = "/dev/nvme0n1";
      filesystem = "ext4";
    };
    networking = {
      primaryInterface = "eno2";
      staticIP         = null;
    };
  };

  # === Boot ===
  boot = {
    loader.systemd-boot.enable      = true;
    loader.efi.canTouchEfiVariables = true;

    # ZFS support
    supportedFilesystems = [ "zfs" ];
    zfs.forceImportRoot  = false;

    # Intel QuickSync / i915 for Jellyfin hardware transcoding
    initrd.kernelModules             = [ "i915" ];
    kernelParams                     = [ "i915.enable_guc=2" ];
  };

  # === ZFS ===
  services.zfs = {
    autoScrub.enable   = true;
    autoScrub.interval = "weekly";
    trim.enable        = true;
  };

  # Required for ZFS
  networking.hostId = "459e90fe";  # required for ZFS — unique per host

  # === Networking ===
  networking = {
    hostName              = "horologium";
    networkmanager.enable = true;
    firewall = {
      enable            = true;
      allowedTCPPorts   = [
        8096   # Jellyfin HTTP
        8920   # Jellyfin HTTPS
        7359   # Jellyfin auto-discovery
      ];
      allowedUDPPorts = [
        7359   # Jellyfin auto-discovery
        1900   # Jellyfin DLNA
      ];
    };
  };

  # === Intel QuickSync (hardware transcoding) ===
  hardware.graphics = {
    enable       = true;
    extraPackages = with pkgs; [
      intel-media-driver    # VAAPI for 11th+ gen
      intel-vaapi-driver    # VAAPI for older gen (fallback)
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # === Docker ===
  virtualisation.docker = {
    enable          = true;
    enableOnBoot    = true;
    autoPrune.enable = true;
  };

  users.users.xeseuses.extraGroups = [ "wheel" "docker" "video" "render" ];

  # === Media Services (Docker) ===
  virtualisation.oci-containers.backend    = "docker";
  virtualisation.oci-containers.containers = {

    # ── Jellyfin ────────────────────────────────────────────────────────────
    jellyfin = {
      image   = "jellyfin/jellyfin:latest";
      volumes = [
        "/var/lib/jellyfin/config:/config"
        "/var/lib/jellyfin/cache:/cache"
        "/media:/media:ro"
        "/dev/dri:/dev/dri"           # Intel QuickSync device passthrough
      ];
      ports       = [ "8096:8096" "8920:8920" "7359:7359/udp" "1900:1900/udp" ];
      environment = {
        JELLYFIN_PublishedServerUrl = "http://horologium.lan:8096";
      };
      extraOptions = [
        "--device=/dev/dri/renderD128"  # Intel QuickSync
        "--group-add=video"
        "--network=host"
      ];
      autoStart = true;
    };

    # ── Prowlarr (indexer manager) ───────────────────────────────────────────
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

    # ── Sonarr (TV) ──────────────────────────────────────────────────────────
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

    # ── Radarr (movies) ──────────────────────────────────────────────────────
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

    # ── Bazarr (subtitles) ────────────────────────────────────────────────────
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

  };

  # Persistent data directories
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin/config 0755 root root -"
    "d /var/lib/jellyfin/cache  0755 root root -"
    "d /var/lib/prowlarr         0755 root root -"
    "d /var/lib/sonarr           0755 root root -"
    "d /var/lib/radarr           0755 root root -"
    "d /var/lib/bazarr           0755 root root -"
  ];

  # === Users ===
  users.users.xeseuses = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets."users/xeseuses/hashedPassword".path;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  # === System ===
  services.openssh.enable          = true;
  security.sudo.wheelNeedsPassword = false;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.05";
}

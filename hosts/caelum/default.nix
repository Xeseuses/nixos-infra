{ config, pkgs, ... }:
let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    django
    pillow
    sqlparse
    gunicorn
  ]);
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  asthrossystems = {
    hostInfo = "Beelink EQ12 - Services Host";
    isServer = true;
  };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernelModules = [ "kvm-intel" ];
  };

  sops = {
  defaultSopsFile = ../../secrets/secrets.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";
  secrets."caelum/solibieb/env" = {
    owner = "solibieb";
    group = "solibieb";
  };
  secrets."caelum/unifi/mongo-db-env" = {};
  secrets."caelum/unifi/unifi-env" = {};
};
  
  networking = {
    hostName = "caelum";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 2283 13378 2335 8443 8080 9040 ];
      allowedUDPPorts = [ 3478 10001 9053 ];
      trustedInterfaces = [ "wg0" ];
    };
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.200.0.3/24" ];
    privateKeyFile = "/var/lib/wireguard/private.key";
    peers = [{
      publicKey = "TPGNC4CP2U75ZMvWW2KP7hba/4RqeDYZZsbmfJPMG1o=";
      allowedIPs = [ "10.200.0.0/24" ];
      endpoint = "77.42.83.12:51821";
      persistentKeepalive = 25;
    }];
  };

  # ── Docker ────────────────────────────────────────────────────────────────
  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";

  # Create isolated Docker network for UniFi + MongoDB to talk to each other
  systemd.services.init-unifi-network = {
    description = "Create docker network for unifi";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      ${pkgs.docker}/bin/docker network inspect unifi-net >/dev/null 2>&1 || \
      ${pkgs.docker}/bin/docker network create unifi-net
    '';
  };

  virtualisation.oci-containers.containers = {

    # UniFi Network Application
    unifi = {
      image = "lscr.io/linuxserver/unifi-network-application:latest";
      dependsOn = [ "unifi-db" ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Amsterdam";
        MONGO_USER = "unifi";
        MONGO_HOST = "unifi-db";
        MONGO_PORT = "27017";
        MONGO_DBNAME = "unifi";
        MONGO_AUTHSOURCE = "admin";
      };

      environmentFiles = [
        config.sops.secrets."caelum/unifi/unifi-env".path
      ];   
  
      volumes = [ "/var/lib/unifi:/config" ];
      ports = [
        "8443:8443"   # Web UI (HTTPS)
        "8080:8080"   # AP inform port — APs phone home here
        "3478:3478/udp" # STUN
        "10001:10001/udp" # AP discovery
      ];
      extraOptions = [ "--network=unifi-net" ];
    };

    # MongoDB for UniFi (must be 4.4 — newer versions unsupported by UniFi)
    unifi-db = {
      image = "mongo:4.4";
      volumes = [
        "/var/lib/unifi-db:/data/db"
        "/var/lib/unifi-db-init:/docker-entrypoint-initdb.d"
      ];
      environment = {
        MONGO_INITDB_ROOT_USERNAME = "root";
      };
      environmentFiles = [
       config.sops.secrets."caelum/unifi/mongo-db-env".path
      ];
      extraOptions = [ "--network=unifi-net" ];
    };

  };

  # ── Samba ─────────────────────────────────────────────────────────────────
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      myshare = {
        path = "/srv/shared";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "xeseuses";
      };
    };
  };

  # ── Hardware / GPU ────────────────────────────────────────────────────────
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # ── Solibieb ──────────────────────────────────────────────────────────────
  users.users.solibieb = {
    isSystemUser = true;
    group = "solibieb";
    home = "/var/lib/solibieb";
  };
  users.groups.solibieb = {};

  systemd.services.solibieb = {
    description = "Solibieb Django App";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      DJANGO_SETTINGS_MODULE = "solibieb_portal.settings";
    };
    serviceConfig = {
      ExecStartPre = "${pythonEnv}/bin/python manage.py collectstatic --noinput";
      ExecStart = "${pythonEnv}/bin/gunicorn --workers 2 --bind 127.0.0.1:2335 solibieb_portal.wsgi:application";
      WorkingDirectory = "/var/lib/solibieb";
      User = "solibieb";
      Group = "solibieb";
      Restart = "on-failure";
      EnvironmentFile = config.sops.secrets."caelum/solibieb/env".path;
    };
  };

  # nginx — solibieb moved to port 8081 (8080 now used by UniFi AP inform)
  services.nginx = {
    enable = true;
    virtualHosts."solibieb" = {
      listen = [{ addr = "10.200.0.3"; port = 8081; }];
      locations."/static/".alias = "/var/lib/solibieb/static/";
      locations."/media/".alias = "/var/lib/solibieb/media/";
      locations."/".proxyPass = "http://127.0.0.1:2335";
    };
  };

  networking.interfaces.enp2s0.ipv4.routes = [{
  address = "10.200.0.0";
  prefixLength = 24;
  via = "10.40.40.104";  # route WireGuard subnet replies via andromeda
}];
  
  # ── Tor (transparent proxy for VLAN60) ───────────────────────────────────
services.tor = {
  enable = true;
  settings = {
    TransPort = [{ addr = "0.0.0.0"; port = 9040; }];
    DNSPort   = [{ addr = "0.0.0.0"; port = 9053; }];
    VirtualAddrNetworkIPv4 = "10.192.0.0/10";
    ExitPolicy = "reject *:*";
  };
};


  # ── Users ─────────────────────────────────────────────────────────────────
  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    hashedPassword = "$6$uayRJfzzuS1czsdA$62tPdKk0wiwtI78hfu.3BocdQ1YTwadRtxUuB7fUrMYPhFYTiJgCi0tsOOwhFLLh8JoAUIV0G.j0IvT11Wuua0";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  # ── Packages ──────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    vim
    neovim
    docker-compose
    curl
    htop
    ncdu
    ffmpeg-full
    python315
  ];

  # ── Misc ──────────────────────────────────────────────────────────────────
  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "23.11";
}


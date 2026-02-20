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

  networking = {
    hostName = "caelum";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 2283 13378 2335 ];
      trustedInterfaces = [ "wg0" ];
    };
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.200.0.3/24" ];
    privateKeyFile = "/var/lib/wireguard/private.key";
    peers = [{
      publicKey = "1wUDy/NFm7QSCnSGSHd26YDLcN3SUGIy7PePpG/WyU0=";
      allowedIPs = [ "10.200.0.0/24" ];
      endpoint = "172.245.52.108:51821";
      persistentKeepalive = 25;
    }];
  };

  virtualisation.docker.enable = true;

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

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # Solibieb user
  users.users.solibieb = {
    isSystemUser = true;
    group = "solibieb";
    home = "/var/lib/solibieb";
  };
  users.groups.solibieb = {};

  # Solibieb Django service
  systemd.services.solibieb = {
    description = "Solibieb Django App";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      DJANGO_SETTINGS_MODULE = "solibieb_portal.settings";
    };
    serviceConfig = {
      ExecStart = "${pythonEnv}/bin/gunicorn --workers 2 --bind 127.0.0.1:2335 solibieb_portal.wsgi:application";
      WorkingDirectory = "/var/lib/solibieb";
      User = "solibieb";
      Group = "solibieb";
      Restart = "on-failure";
      # Simple env file instead of sops for now
      EnvironmentFile = "/var/lib/solibieb/.env";
    };
  };

  # nginx to serve static/media and proxy to gunicorn
  services.nginx = {
    enable = true;
    virtualHosts."solibieb" = {
      listen = [{ addr = "10.200.0.3"; port = 8080; }];
      locations."/static/".alias = "/var/lib/solibieb/static/";
      locations."/media/".alias = "/var/lib/solibieb/media/";
      locations."/".proxyPass = "http://127.0.0.1:2335";
    };
  };

  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    hashedPassword = "$6$uayRJfzzuS1czsdA$62tPdKk0wiwtI78hfu.3BocdQ1YTwadRtxUuB7fUrMYPhFYTiJgCi0tsOOwhFLLh8JoAUIV0G.j0IvT11Wuua0";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

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

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "23.11";
}

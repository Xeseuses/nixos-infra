{ config, pkgs, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../modules/nixos/optional/media-server.nix
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
    supportedFilesystems             = [ "zfs" ];
    zfs.forceImportRoot              = false;
    initrd.kernelModules             = [ "i915" ];
    kernelParams                     = [ "i915.enable_guc=2" ];
  };

  # === ZFS ===
  networking.hostId = "1f17bed9";
  services.zfs = {
    autoScrub.enable   = true;
    autoScrub.interval = "weekly";
    trim.enable        = true;
  };

  # === Networking ===
  networking = {
    hostName              = "horologium";
    networkmanager.enable = true;
    firewall = {
      enable          = true;
      allowedTCPPorts = [ 8096 8920 7359 9696 8989 7878 6767 8080 ];
      allowedUDPPorts = [ 7359 1900 ];
    };
  };

  # === Intel QuickSync (hardware transcoding) ===
  hardware.graphics = {
    enable        = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  networking.firewall.checkReversePath = false;

  # === Users ===
  users.users.xeseuses = {
    isNormalUser       = true;
    extraGroups        = [ "wheel" "docker" "video" "render" ];
    hashedPasswordFile = config.sops.secrets."users/xeseuses/hashedPassword".path;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };
 
  users.groups.media = {};
users.users.media = {
  isSystemUser = true;
  group = "media";
  uid = 1000; # keep 1000 if your files already use it
};

  # === System ===
  services.openssh.enable          = true;
  security.sudo.wheelNeedsPassword = false;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.05";
}


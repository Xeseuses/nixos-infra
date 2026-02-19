{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  asthrossystems = {
    hostInfo = "andromeda - Beelink EQ12 - Home Assistant host";
    isServer = true;
    
    features = {
      impermanence = false;
      encryption = false;
      binaryCache.enable = false;
      
      # Home Assistant microVM
      homeAssistant = {
        enable = true;
        skyConnect = {
          vendorId = "10c4";  # Find with: lsusb
          productId = "ea60";
        };
        macAddress = "02:00:00:00:00:01";
        ipAddress = "10.40.10.50";
      };
    };
    
    storage = {
      rootDisk = "/dev/nvme0n1";
      filesystem = "ext4";
    };
  };

  networking.hostName = "andromeda";

  # SOPS for restic password
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets."restic/andromeda" = {};
  };

  # Restic backup
  services.restic.backups.haos = {
    repository = "sftp:xeseuses@10.40.40.104:/var/backups/restic/andromeda-haos";
    paths = [ "/var/lib/microvms/haos/shares/haos-data" ];
    passwordFile = config.sops.secrets."restic/andromeda".path;
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 3"
    ];
  };

  system.stateVersion = "24.11";
}

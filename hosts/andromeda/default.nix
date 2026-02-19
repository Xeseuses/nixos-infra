{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules/nixos/common
    ../../modules/nixos/optional/microvm-haos.nix
  ];

  asthrossystems = {
    hostInfo = "andromeda - Beelink EQ12 - Home Assistant host";
    isServer = true;

    features = {
      # Keeping it simple like eridanus - no encryption, no impermanence
      impermanence = false;
      encryption = false;
      binaryCache.enable = false;
    };

    storage = {
      rootDisk = "/dev/nvme0n1";
      filesystem = "ext4";
    };
  };

  networking.hostName = "andromeda";

  # microvm.nix host capability
  microvm.host.enable = true;

  # HAOS microvm - defined in modules/nixos/optional/microvm-haos.nix
  asthrossystems.homeAssistant = {
    enable = true;

    # Sky Connect USB dongle - find with: lsusb | grep -i nabu
    # Usually: 10c4:ea60 (Silicon Labs CP210x) or 1a86:55d4
    # Fill in after first boot on andromeda: lsusb
    skyConnect = {
      vendorId = "10c4";
      productId = "ea60";
    };

    # HAOS gets its own IP on VLAN 10 via bridge
    # Set a static IP for your HAOS instance here
    macAddress = "02:00:00:00:00:01"; # deterministic, change if needed
  };

  # Restic backup of HAOS persistent volume to eridanus
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

  sops.secrets."restic/andromeda" = {};

  system.stateVersion = "24.11";
}


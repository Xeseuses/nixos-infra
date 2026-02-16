{ config, lib, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
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
    hostInfo = "Beelink EQ12, Intel N100, 16GB RAM, 2TB NVMe";
    isServer = true;

    features = {
      impermanence = false;
      secureBoot = false;
      encryption = false;

      # Enable backups
      backup = {
        enable = true;

        targets = {
          # Backup system config
          system = {
            repository = "/var/backups/restic/system";
            paths = [
              "/home/xeseuses/nixos-infra"
              "/etc/nixos"
            ];
            schedule = "daily";
          };

          # Backup user data
          home = {
            repository = "/var/backups/restic/home";
            paths = [
              "/home/xeseuses/Documents"
              "/home/xeseuses/.ssh"
            ];
            schedule = "daily";
          };
        };
      };
    };

    storage = {
      rootDisk = "/dev/nvme0n1";
      filesystem = "ext4";
    };

    networking = {
      primaryInterface = "enp1s0";
      staticIP = null;
    };
  };

  # === Boot Configuration ===
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  # === Networking ===
  networking.hostName = "eridanus";

  # === User Password from SOPS ===
  users.users.xeseuses.hashedPasswordFile =
    config.sops.secrets."users/xeseuses/hashedPassword".path;

  # === State Version ===
  system.stateVersion = "24.11";
}


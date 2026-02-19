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
      "restic_password" = {};
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

      # Binary cache server
      binaryCache = {
        enable = true;
        server = "cache.home.arpa";
      };

      # Backups
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
      staticIP = 10.40.40.104;
    };
  };

  # === Boot Configuration ===
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  # === Networking ===
  networking = {
    hostName = "eridanus";
    
    # Disable DHCP globally
    useDHCP = false;
    
    # Configure static IP on enp1s0
    interfaces.enp1s0 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "10.40.40.105";
        prefixLength = 24;
      }];
    };
    
    # Set gateway and DNS
    defaultGateway = "10.40.40.1";
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 5000 ];  # SSH + binary cache
    };
  };
  # === User Configuration ===
  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets."users/xeseuses/hashedPassword".path;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  # === State Version ===
  system.stateVersion = "24.11";
}


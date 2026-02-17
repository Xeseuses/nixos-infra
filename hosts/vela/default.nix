# hosts/vela/default.nix
{ config, pkgs, ... }:
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
    hostInfo = "ASUS ROG Flow Z13, Intel i7-12700H, 16GB RAM, Touchscreen";
    
    isDesktop = true;
    isLaptop = true;
    
    features = {
      impermanence = true;
      secureBoot = false;
      encryption = true;
      touchscreen = true;
      asusRog = true;
      noctalia = true;

      desktop = "niri";              # ← Niri compositor
      graphics = "hybrid";    # ← Intel + NVIDIA
 
      backup = {
        enable = true;
        targets = {
          system = {
            repository = "/var/backups/restic/system";
            paths = [ "/home/xeseuses/nixos-infra" ];
            schedule = "daily";
          };
          home = {
            repository = "/var/backups/restic/home";
            paths = [
              "/home/xeseuses/Documents"
              "/home/xeseuses/Pictures"
              "/home/xeseuses/.ssh"
            ];
            schedule = "daily";
          };
        };
      };
    };
    
    storage = {
      rootDisk = "/dev/nvme0n1";
      filesystem = "btrfs";
    };
    
    networking = {
      primaryInterface = "wlo1";  # WiFi (check during install)
      staticIP = null;
    };
  };

  # === Boot ===
  boot = {
  loader.systemd-boot.enable = true;
  loader.efi.canTouchEfiVariables = true;
  
   initrd = {
    availableKernelModules = [ 
      "xhci_pci" "thunderbolt" "nvme" "usb_storage" "sd_mod"
    ];
    
    luks.devices."cryptroot" = {
      device = "/dev/nvme0n1p2";  # Direct, no labels!
      allowDiscards = true;
    };
  };

  kernelParams = [ 
    "quiet" 
    "splash"
    "nvidia-drm.modeset=1"
  ];
  
  # Resume from hibernate
  resumeDevice = "/dev/mapper/cryptroot";
  };

  # === Networking ===
  networking.hostName = "vela";
  networking.networkmanager.wifi.powersave = true;

  # === User ===
  users.users.xeseuses = {
    # Password from SOPS
    hashedPasswordFile = config.sops.secrets."users/xeseuses/hashedPassword".path;
    
    # Create home directory in /persist
    home = "/persist/home/xeseuses";
  };

  # Symlink /home/xeseuses -> /persist/home/xeseuses
  systemd.tmpfiles.rules = [
    "L+ /home/xeseuses - - - - /persist/home/xeseuses"
  ];

    # === State Version ===
  system.stateVersion = "24.11";
}

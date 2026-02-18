# modules/options.nix
{ lib, ... }:
{
  options.asthrossystems = {
    
    hostInfo = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Human-readable host information";
    };
    
    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "/home/xeseuses/nixos-infra";
      description = "Path to the flake repository";
    };
    
    isRouter = lib.mkEnableOption "router functionality";
    isServer = lib.mkEnableOption "server functionality";
    isDesktop = lib.mkEnableOption "desktop functionality";
    isLaptop = lib.mkEnableOption "laptop functionality";
    
    features = {
      impermanence = lib.mkEnableOption "impermanence (ephemeral root)";
      secureBoot = lib.mkEnableOption "secure boot with lanzaboote";
      encryption = lib.mkEnableOption "full disk encryption";
      microVMs = lib.mkEnableOption "microVM support";
      touchscreen = lib.mkEnableOption "touchscreen support";
      asusRog = lib.mkEnableOption "ASUS ROG laptop support";
      
      desktop = lib.mkOption {
        type = lib.types.enum [ "none" "kde" "gnome" "niri" ];
        default = "none";
        description = "Desktop environment to use";
      };
      
      graphics = lib.mkOption {
        type = lib.types.enum [ "none" "intel" "amd" "nvidia" "nvidia-hybrid" ];
        default = "none";
        description = "Graphics driver configuration";
      };
      
      # Binary cache - at THIS level, not nested!
      binaryCache = {
        enable = lib.mkEnableOption "binary cache server";
        
        server = lib.mkOption {
          type = lib.types.str;
          default = "cache.home.arpa";
          description = "Cache server hostname";
        };
      };
      
      # Backup is separate
      backup = {
        enable = lib.mkEnableOption "restic backups";
        
        targets = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              repository = lib.mkOption {
                type = lib.types.str;
                description = "Restic repository path";
              };
              paths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Paths to backup";
              };
              timerConfig = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { OnCalendar = "daily"; };
                description = "Systemd timer configuration";
              };
            };
          });
          default = {};
          description = "Backup targets";
        };
      };
    };
    
    networking = {
      vlans = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [];
        description = "VLAN IDs to configure";
      };
      
      primaryInterface = lib.mkOption {
        type = lib.types.str;
        default = "eth0";
        description = "Primary network interface";
      };
      
      staticIP = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static IP address";
      };
    };
    
    storage = {
      rootDisk = lib.mkOption {
        type = lib.types.str;
        default = "/dev/sda";
        description = "Root disk device";
      };
      
      filesystem = lib.mkOption {
        type = lib.types.enum [ "ext4" "btrfs" "zfs" ];
        default = "ext4";
        description = "Root filesystem type";
      };
      
      zfs = {
        enable = lib.mkEnableOption "ZFS storage pool";
        
        poolName = lib.mkOption {
          type = lib.types.str;
          default = "tank";
          description = "ZFS pool name";
        };
        
        datasets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "ZFS datasets to create";
        };
      };
    };
  };
}

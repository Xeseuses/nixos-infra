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
      
      binaryCache = {
        enable = lib.mkEnableOption "binary cache server";
        server = lib.mkOption {
          type = lib.types.str;
          default = "cache.home.arpa";
          description = "Cache server hostname";
        };
      };
      
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
              schedule = lib.mkOption {
                type = lib.types.str;
                default = "daily";
                description = "Systemd OnCalendar value";
              };
            };
          });
          default = {};
          description = "Backup targets";
        };
      };
      homeAssistant = {
       enable = lib.mkEnableOption "Home Assistant microVM";

       skyConnect = {
        vendorId = lib.mkOption {
         type = lib.types.str;
         default = "10c4";
         description = "USB vendor ID for Sky Connect";
      };

       productId = lib.mkOption {
        type = lib.types.str;
        default = "ea60";
        description = "USB product ID for Sky Connect";
      };
    };

    macAddress = lib.mkOption {
      type = lib.types.str;
      default = "02:00:00:00:00:01";
      description = "MAC address for HAOS VM";
    };

    ipAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.40.10.50";
      description = "Static IP for HAOS";
    };
  };
      # Router features
      router = {
        enable = lib.mkEnableOption "router functionality";
        
        vpn = {
          enable = lib.mkEnableOption "Mullvad VPN";
          configFile = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/wireguard/mullvad.conf";
            description = "Path to Mullvad WireGuard config";
          };
          vlans = lib.mkOption {
            type = lib.types.listOf lib.types.int;
            default = [ 20 30 ];
            description = "VLANs that should route through VPN";
          };
        };
      };
    };
    
    networking = {
      # Simple VLAN list (for servers)
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
      
      # Router-specific options
      wanInterface = lib.mkOption {
        type = lib.types.str;
        default = "enp1s0";
        description = "WAN interface (to internet)";
      };
      
      lanInterface = lib.mkOption {
        type = lib.types.str;
        default = "enp2s0";
        description = "LAN trunk interface (to switch)";
      };
      
      # VLAN configurations for router
      vlanConfig = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.int;
              description = "VLAN ID";
            };
            
            subnet = lib.mkOption {
              type = lib.types.str;
              description = "Subnet in CIDR notation";
              example = "10.40.10.0/24";
            };
            
            gateway = lib.mkOption {
              type = lib.types.str;
              description = "Gateway IP for this VLAN";
              example = "10.40.10.1";
            };
            
            dhcpRange = lib.mkOption {
              type = lib.types.str;
              description = "DHCP range";
              example = "10.40.10.100-10.40.10.200";
            };
            
            allowedVlans = lib.mkOption {
              type = lib.types.listOf lib.types.int;
              default = [];
              description = "VLANs this VLAN can access";
            };
          };
        });
        default = {};
        description = "VLAN configurations for router";
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

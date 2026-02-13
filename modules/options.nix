# modules/options.nix
{ lib, ... }:
{
  options.asthrossystems = {
    # === Machine Information ===
    hostInfo = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Human-readable description of this machine's hardware";
      example = "Beelink EQ12, Intel N100, 16GB RAM, 500GB NVMe";
    };

    flakePath = lib.mkOption {
      type = lib.types.path;
      default = "/home/xeseuses/nixos-infra";
      description = "Path to the nixos-infra repository on this machine";
    };

    # === Machine Type (only one should be true) ===
    isRouter = lib.mkEnableOption "router functionality";
    isServer = lib.mkEnableOption "server functionality";
    isDesktop = lib.mkEnableOption "desktop functionality";

    # === Features (can combine) ===
    features = {
      impermanence = lib.mkEnableOption "impermanence (wipe root on boot)";
      secureBoot = lib.mkEnableOption "secure boot with lanzaboote";
      encryption = lib.mkEnableOption "disk encryption";
      microVMs = lib.mkEnableOption "MicroVM host capabilities";
      
      backup = {
        enable = lib.mkEnableOption "automated backups";
        
        targets = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              repository = lib.mkOption {
                type = lib.types.str;
                description = "Restic repository path";
              };
              
              paths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = "Paths to backup";
              };
              
              schedule = lib.mkOption {
                type = lib.types.str;
                default = "daily";
                description = "Backup schedule (systemd timer format)";
              };
            };
          });
          default = {};
          description = "Backup target definitions";
        };
      };
    };

    # === Networking ===
    networking = {
      vlans = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "VLANs this machine should be connected to";
        example = [ "server" "management" ];
      };

      primaryInterface = lib.mkOption {
        type = lib.types.str;
        default = "eth0";
        description = "Primary network interface name";
      };

      staticIP = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static IP address if not using DHCP";
        example = "10.0.10.5/24";
      };
    };

    # === Storage ===
    storage = {
      rootDisk = lib.mkOption {
        type = lib.types.str;
        description = "Main disk device for OS installation";
        example = "/dev/nvme0n1";
      };

      filesystem = lib.mkOption {
        type = lib.types.enum [ "ext4" "btrfs" "zfs" "xfs" ];
        default = "ext4";
        description = "Root filesystem type";
      };

      zfs = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = {
            poolName = lib.mkOption {
              type = lib.types.str;
              default = "tank";
              description = "ZFS pool name";
            };

            topology = lib.mkOption {
              type = lib.types.enum [ "mirror" "raidz1" "raidz2" "stripe" ];
              default = "mirror";
              description = "ZFS pool topology";
            };

            disks = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "List of disks for ZFS pool";
              example = [ "/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd" ];
            };
          };
        });
        default = null;
        description = "ZFS configuration (if using ZFS)";
      };
    };

    # === Services ===
    services = {
      reverseProxy = {
        enable = lib.mkEnableOption "reverse proxy (Caddy)";
        
        upstreamHost = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Hostname of upstream server to proxy to";
          example = "router";
        };
      };
    };
  };
}

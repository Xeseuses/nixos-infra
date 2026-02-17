# hosts/vela/disk-config.nix
{ ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            
            # Boot partition (unencrypted)
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            
            # Encrypted root
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                
                settings = {
                  allowDiscards = true;  # SSD TRIM
                };
                
                # Prompt for password during install
                passwordFile = "/tmp/luks-password";
                
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  
                  subvolumes = {
                    # Root - WIPED on boot!
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    
                    # Persistent data
                    "@persist" = {
                      mountpoint = "/persist";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    
                    # Nix store
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    
                    # Logs
                    "@log" = {
                      mountpoint = "/var/log";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    
                    # Swap
                    "@swap" = {
                      mountpoint = "/.swapvol";
                      swap.swapfile.size = "16G";
                    };
                  };
                  
                  # Create blank snapshot for impermanence
                  postCreateHook = ''
                    MNTPOINT=$(mktemp -d)
                    mount -t btrfs /dev/mapper/cryptroot "$MNTPOINT" -o subvol=/
                    trap 'umount $MNTPOINT; rm -rf $MNTPOINT' EXIT
                    btrfs subvolume snapshot -r "$MNTPOINT/@" "$MNTPOINT/@-blank"
                  '';
                };
              };
            };
          };
        };
      };
    };
  };
  
  # These need to be available early
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
}

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
            
            # Boot partition
            boot = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            
            # Encrypted root
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                
                settings = {
                  allowDiscards = true;
                };
                
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  
                  subvolumes = {
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    
                    "@persist" = {
                      mountpoint = "/persist";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    
                    "@log" = {
                      mountpoint = "/var/log";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    
                    "@swap" = {
                      mountpoint = "/.swapvol";
                      swap.swapfile.size = "16G";
                    };
                  };
                  
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
  
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
}

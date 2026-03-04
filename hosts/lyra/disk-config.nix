{ ... }:
{
  disko.devices = {
    disk.sda = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";  # BIOS boot partition for GRUB
          };
          swap = {
            size = "2G";
            content = {
              type = "swap";
              randomEncryption = false;
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              extraArgs = [ "-L" "nixos" ];  # label the partition
            };
          };
        };
      };
    };
  };
}


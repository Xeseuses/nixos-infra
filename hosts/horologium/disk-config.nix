{ lib, ... }:
{
  disko.devices = {

    # ── OS disk (NVMe) ──────────────────────────────────────────────────────
    disk.nvme0n1 = {
      type    = "disk";
      device  = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size    = "1G";
            type    = "EF00";
            content = {
              type       = "filesystem";
              format     = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size    = "100%";
            content = {
              type       = "filesystem";
              format     = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };

    # ── ZFS mirror disks ────────────────────────────────────────────────────
    disk.sda = { type = "disk"; device = "/dev/sda"; content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "media"; }; }; }; };
    disk.sdb = { type = "disk"; device = "/dev/sdb"; content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "media"; }; }; }; };
    disk.sdc = { type = "disk"; device = "/dev/sdc"; content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "media"; }; }; }; };
    disk.sdd = { type = "disk"; device = "/dev/sdd"; content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "media"; }; }; }; };

    # ── ZFS pool ─────────────────────────────────────────────────────────────
    zpool.media = {
      type = "zpool";
      mode = "mirror";  # disko will mirror sda+sdb+sdc+sdd as one big mirror

      options = {
        ashift   = "12";
        autotrim = "on";
      };

      rootFsOptions = {
        compression                = "zstd";
        atime                      = "off";
        xattr                      = "sa";
        acltype                    = "posixacl";
        "com.sun:auto-snapshot"    = "false";
      };

      datasets = {
        "movies" = {
          type       = "zfs_fs";
          mountpoint = "/media/movies";
        };
        "tv" = {
          type       = "zfs_fs";
          mountpoint = "/media/tv";
        };
        "downloads" = {
          type       = "zfs_fs";
          mountpoint = "/media/downloads";
        };
        "music" = {
          type       = "zfs_fs";
          mountpoint = "/media/music";
        };
      };
    };
  };
}

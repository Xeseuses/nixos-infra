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
            size     = "1G";
            type     = "EF00";
            content  = {
              type   = "filesystem";
              format = "vfat";
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

    # ── ZFS media pool (2x mirror: sda+sdb, sdc+sdd) ───────────────────────
    zpool.media = {
      type = "zpool";
      mode = {
        topology = {
          type   = "topology";
          vdevs  = [
            { mode    = "mirror"; members = [ "sda" "sdb" ]; }
            { mode    = "mirror"; members = [ "sdc" "sdd" ]; }
          ];
        };
      };

      options = {
        ashift          = "12";   # 4K sectors
        autotrim        = "on";   # SSDs benefit from trim
      };

      rootFsOptions = {
        compression     = "zstd";
        atime           = "off";
        xattr           = "sa";
        acltype         = "posixacl";
        "com.sun:auto-snapshot" = "false";
      };

      datasets = {
        "media" = {
          type    = "zfs_fs";
          mountpoint = "/media";
          options.mountpoint = "legacy";
        };
        "media/movies" = {
          type    = "zfs_fs";
          mountpoint = "/media/movies";
          options.mountpoint = "legacy";
        };
        "media/tv" = {
          type    = "zfs_fs";
          mountpoint = "/media/tv";
          options.mountpoint = "legacy";
        };
        "media/downloads" = {
          type    = "zfs_fs";
          mountpoint = "/media/downloads";
          options.mountpoint = "legacy";
        };
        "media/music" = {
          type    = "zfs_fs";
          mountpoint = "/media/music";
          options.mountpoint = "legacy";
        };
      };
    };
  };

  # Mount ZFS datasets
  fileSystems = {
    "/media"           = { device = "media/media";     fsType = "zfs"; };
    "/media/movies"    = { device = "media/media/movies";    fsType = "zfs"; };
    "/media/tv"        = { device = "media/media/tv";        fsType = "zfs"; };
    "/media/downloads" = { device = "media/media/downloads"; fsType = "zfs"; };
    "/media/music"     = { device = "media/media/music";     fsType = "zfs"; };
  };
}


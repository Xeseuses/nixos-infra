# modules/nixos/optional/zfs.nix
{ config, lib, pkgs, ... }:

lib.mkIf (config.myinfra.storage.filesystem == "zfs") {
  
  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  
  # Required for ZFS
  networking.hostId = builtins.substring 0 8 (
    builtins.hashString "md5" config.networking.hostName
  );

  # Auto-snapshots
  services.zfs.autoSnapshot = {
    enable = true;
    frequent = 4;   # 15-min snapshots, keep 4
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 12;
  };

  # Auto-scrub monthly
  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = [ config.myinfra.storage.zfs.poolName ];
  };

  # Email notifications for ZFS events
  services.zfs.zed = {
    enableMail = false;  # Set to true if you configure email
    settings = {
      ZED_EMAIL_ADDR = [ "root" ];
      ZED_NOTIFY_VERBOSE = true;
    };
  };
}

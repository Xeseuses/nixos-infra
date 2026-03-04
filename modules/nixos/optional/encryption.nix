# modules/nixos/optional/encryption.nix
{ config, lib, ... }:

lib.mkIf config.myinfra.features.encryption {
  
  # Boot needs to unlock disk
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/...";  # Encrypted partition
    preLVM = true;  # Unlock before LVM
    allowDiscards = true;  # SSD TRIM support
  };
  
  # Persist LUKS header (if using impermanence)
  # (Actually, this is on the encrypted partition, so it persists automatically)
}

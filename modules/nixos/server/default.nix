# modules/nixos/server/default.nix
{ config, lib, ... }:
{
  imports = [
    ./backups.nix
    ./monitoring.nix
    ./networking.nix
  ];
  
  # Common server settings
  
  # No GUI on servers
  services.xserver.enable = lib.mkDefault false;
  
  # Automatic updates (security patches)
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;  # Don't auto-reboot
    dates = "04:00";      # Check at 4 AM
  };
}

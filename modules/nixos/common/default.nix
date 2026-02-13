# modules/nixos/common/default.nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ./nix.nix
    ./ssh.nix
    ./users.nix
  ];
  
  # Common settings for ALL NixOS machines
  
  # Enable firmware
  hardware.enableRedistributableFirmware = true;
  
  # Timezone
  time.timeZone = lib.mkDefault "Europe/Amsterdam";  # Adjust to your timezone
  
  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  
  # Console keymap
  console.keyMap = "us";
}

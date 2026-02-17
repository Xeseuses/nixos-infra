# modules/nixos/optional/laptop.nix
{ config, lib, pkgs, ... }:
lib.mkIf config.asthrossystems.isLaptop {

  # Power management
  # Use power-profiles-daemon OR tlp, never both!
  services.power-profiles-daemon.enable = true;

  # Laptop-specific services
  services.logind = {
    lidSwitch = "suspend";
    lidSwitchExternalPower = "suspend";
  };

  # Thermal management
  services.thermald.enable = true;

  # Battery monitoring
  services.upower.enable = true;

  # Enable fstrim for SSD
  services.fstrim.enable = true;

  # Laptop packages
  environment.systemPackages = with pkgs; [
    powertop
    acpi
    brightnessctl
  ];
}

# modules/nixos/optional/laptop.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.asthrossystems.isLaptop {
  
  # Power management (no TLP with NVIDIA hybrid)
  services.power-profiles-daemon.enable = lib.mkDefault true;
  
  # For ASUS ROG, we use asusctl instead of TLP
  services.tlp.enable = lib.mkIf (!config.asthrossystems.features.asusRog) true;
  
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
  
  # Persist power settings
  environment.persistence."/persist" = lib.mkIf config.asthrossystems.features.impermanence {
    directories = [
      "/var/lib/upower"
    ];
  };
}

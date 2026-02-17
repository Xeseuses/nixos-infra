{ config, lib, pkgs, ... }:
lib.mkIf config.asthrossystems.isLaptop {

  services.power-profiles-daemon.enable = true;

  # Fixed renamed options
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
  };

  services.thermald.enable = true;
  services.upower.enable = true;
  services.fstrim.enable = true;

  environment.systemPackages = with pkgs; [
    powertop
    acpi
    brightnessctl
  ];
}

# modules/nixos/optional/asus-rog.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.asthrossystems.features.asusRog {
  
  # ASUS kernel modules
  boot.kernelModules = [ "asus-nb-wmi" ];
  boot.kernelParams = [ "asus_nb_wmi.fnlock=1" ];  # Fn lock on by default
  
  # Supergfxctl (GPU switching for ASUS)
  services.supergfxd = {
    enable = true;
  };
  
  # Asusctl (ASUS controls)
  services.asusd = {
    enable = true;
    enableUserService = true;
  };
  
  environment.systemPackages = with pkgs; [
    asusctl          # ASUS control utilities
    supergfxctl      # GPU switching
    
    # GUI for asusctl
    rog-control-center
  ];
  
  # Enable firmware updates
  services.fwupd.enable = true;
  
  # Persist ASUS settings
  environment.persistence."/persist" = lib.mkIf config.asthrossystems.features.impermanence {
    directories = [
      "/var/lib/asusd"
      "/var/lib/supergfxd"
    ];
  };
}

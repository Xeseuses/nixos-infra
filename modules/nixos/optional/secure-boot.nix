# modules/nixos/optional/secure-boot.nix
{ config, lib, pkgs, inputs, ... }:

lib.mkIf config.myinfra.features.secureBoot {
  
  # Import lanzaboote module
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];
  
  # Replace systemd-boot with lanzaboote
  boot.loader.systemd-boot.enable = lib.mkForce false;
  
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";  # Where keys are stored
  };
  
  # Persist secure boot keys (if using impermanence)
  environment.persistence."/persist" = lib.mkIf config.myinfra.features.impermanence {
    directories = [ "/etc/secureboot" ];
  };
}

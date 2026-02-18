# modules/nixos/optional/noctalia.nix
{ config, lib, pkgs, inputs, ... }:

lib.mkIf (config.asthrossystems.features.noctalia) {
  
  # Import noctalia module
  imports = [ inputs.noctalia.nixosModules.default ];
  
  # Enable noctalia
  programs.noctalia = {
    enable = true;
  };
}

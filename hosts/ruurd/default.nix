{ self, config, inputs, lib, minimal, confLib, ... }:

{
  imports = [
     ./hardware-configuration.nix
     ./disk-config.nix
          
     inputs.nixos-hardware.nixosModules.common-cpu-intel
  ];
	
	
  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
 
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  # Enables proprietary firmware
  hardware.enableRedistributableFirmware = true;
	
  asthrossystems = {
    info = "Beelink EQ12, Intel N100, 16GB RAM";
    isImpermanence = false;
    isSecureBoot = false;
    isCrypted = false;
    };

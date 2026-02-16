{
  description = "NixOS Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware";
  
    impermanence.url = "github:nix-community/impermanence";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  }; 

  outputs = { self, nixpkgs, nixos-hardware, disko, sops-nix, ... }: {
    nixosConfigurations = {
      eridanus = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
     	  # Custom Options
          ./modules/options.nix
	  
	  # Common modules
          ./modules/nixos/common
   
 	  # Add backup module 
          ./modules/nixos/optional/backup.nix

 	  # Disko
          disko.nixosModules.disko

	  # Sops
          sops-nix.nixosModules.sops
	 
 	  # Host config
          ./hosts/eridanus
	
	  # Hardware
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-ssd

	vela = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/options.nix
          ./modules/nixos/common
          
     
   	  # Impermanence
          impermanence.nixosModules.impermanence

          # Laptop modules
          ./modules/nixos/optional/backup.nix
          ./modules/nixos/optional/laptop.nix
          ./modules/nixos/optional/desktop-kde.nix
          ./modules/nixos/optional/touchscreen.nix
          ./modules/nixos/optional/graphics-intel.nix
          ./modules/nixos/optional/asus-rog.nix
          
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/vela
          
          # Hardware support
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-laptop
          nixos-hardware.nixosModules.common-pc-laptop-ssd
        ];
      };
    };
  };
}


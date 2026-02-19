# flake.nix
{
  description = "NixOS Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
     sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  
    # Impermanence
    impermanence.url = "github:nix-community/impermanence";
    
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs"; # share your nixpkgs, avoid duplication
    }; 
    
  };

  outputs = { self, nixpkgs, nixos-hardware, disko, sops-nix, impermanence, microvm, ... }: {
    nixosConfigurations = {
      
      eridanus = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/options.nix
          ./modules/nixos/common
          ./modules/nixos/optional/backup.nix
          ./modules/nixos/optional/binary-cache.nix
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/eridanus
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-ssd
        ];
      };
      
      vela = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/options.nix
          ./modules/nixos/common
          ./modules/nixos/optional/backup.nix
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
 	  impermanence.nixosModules.impermanence    
          ./modules/nixos/optional/impermanence.nix 
          ./modules/nixos/optional/desktop-niri.nix  
          ./modules/nixos/optional/laptop.nix   
          ./hosts/vela
        ];
      };
      orion = nixpkgs.lib.nixosSystem {
	system = "x86_64-linux";
	modules = [
           ./modules/options.nix
	   ./modules/nixos/common
	   disko.nixosModules.disko
	   ./hosts/orion
	 ];
	};
       andromeda = nixpkgs.lib.nixosSystem {
	 system = "x86_64-linux";
	 specialArgs = { inherit microvm; };
	 modules = [
	   ./modules/options.nix
	   ./modules/nixos/common
	   disko.nixosModules.disko
	   sops-nix.nixosModules.sops
  	   microvm.nixosModules.host
    	   ./hosts/andromeda
         ];  
       };
    };
  };
}

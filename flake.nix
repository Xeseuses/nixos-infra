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
  };

  outputs = { self, nixpkgs, nixos-hardware, disko, sops-nix, impermanence, ... }: {
    nixosConfigurations = {
      
      eridanus = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/options.nix
          ./modules/nixos/common
          ./modules/nixos/optional/backup.nix
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
          disko.nixosModules.disko
	  ./hosts/vela
	  nixos-hardware.nixosModules.common-cpu-intel
        ];
      };
      
    };
  };
}

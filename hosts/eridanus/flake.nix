{
  description = "NixOS Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
    };
    
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, disko, ... }: {
    
    nixosConfigurations = {
      
      eridanus = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        
        modules = [
          ./modules/options.nix
          disko.nixosModules.disko
          ./hosts/eridanus
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-ssd
        ];
      };
      
    };
    
  };
}

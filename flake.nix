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
   
 	  # Disko
          disko.nixosModules.disko

	  # Sops
          sops-nix.nixosModules.sops
	 
 	  # Host config
          ./hosts/eridanus
	
	  # Hardware
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-ssd
        ];
      };
    };
  };
}


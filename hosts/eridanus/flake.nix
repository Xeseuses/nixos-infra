# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    
    # Add disko
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, disko, ... }: {
    nixosConfigurations.eridanus = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Your options
        ./modules/options.nix
        
        # Disko
        disko.nixosModules.disko
        
        # Host config
        ./hosts/eridanus  # ← Still loads default.nix!
        
        # Hardware
        nixos-hardware.nixosModules.common-cpu-intel
      ];
    };
  };
}

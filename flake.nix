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
    impermanence.url = "github:nix-community/impermanence";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs = { self, nixpkgs, nixos-hardware, disko, sops-nix, impermanence, microvm, nixos-anywhere, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {

    # ── NixOS configurations (hosts) ────────────────────────────────────────
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
          impermanence.nixosModules.impermanence
          ./modules/nixos/optional/impermanence-server.nix
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
          sops-nix.nixosModules.sops
          impermanence.nixosModules.impermanence
          ./modules/nixos/optional/impermanence-server.nix
          ./hosts/orion
        ];
      };

      andromeda = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/options.nix
          ./modules/nixos/common
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          microvm.nixosModules.host
          ./hosts/andromeda
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-ssd
        ];
      };

      lyra = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/options.nix
          ./modules/nixos/common
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          impermanence.nixosModules.impermanence
          ./hosts/lyra
        ];
      };

      caelum = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/options.nix
          ./modules/nixos/common
          ./hosts/caelum
          sops-nix.nixosModules.sops
        ];
      };

      horologium = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/options.nix
          ./modules/nixos/common
          ./hosts/horologium
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
        ];
      };
    
      vanallenbelt = nixpkgs.lib.nixosSystem {
       system = "x86_64-linux";
       modules = [ ./hosts/vanallenbelt/default.nix ];
      };

      kepler = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./hosts/kepler/default.nix ];
      };
    };
      
      # ── Packages ────────────────────────────────────────────────────────────
      packages.${system} = {
       
       xesh-bootstrap = import ./pkgs/xesh-bootstrap/default.nix {
         inherit pkgs;
         inherit (nixos-anywhere.packages.${system}) nixos-anywhere;
       };

       xesh-postinstall = import ./pkgs/xesh-postinstall/default.nix {
         inherit pkgs;
       };
     };
     
      # ── Apps (nix run .#<name>) ──────────────────────────────────────────────
      apps.${system} = {

       xesh-bootstrap = {
         type = "app";
         program = "${self.packages.${system}.xesh-bootstrap}/bin/xesh-bootstrap";
       };

       xesh-postinstall = {
         type = "app";
         program = "${self.packages.${system}.xesh-postinstall}/bin/xesh-postinstall";
       };

     };

  };
}


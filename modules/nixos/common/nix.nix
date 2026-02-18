{ config, lib, pkgs, ...}:
{
  nix = {
  
  # Enable flakes and nix-command 
  settings = {
     experimental-features = ["nix-command" "flakes"];
     
     # Optimize storage
     auto-optimise-store = true;
     
     # Trusted users (can use nix without sudo for some commands)
     trusted-users = [ "root" "@wheel" ];
    
     # Substituters (binart cache servers)
     substituters = [
       "https://cache.nixos.org"
       "http://10.40.40.104:5000"
     ];
    
    trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
   	"cache.home.arpa:dcmEsNlnkWaKUVNpU+s0sDC6W7+2JvaVKGu8fSRnbNE="
      ];
    };
    
    # Automatic garbage collection
    gc = {
     automatic = true;
     dates = "weekly";
     options = "--delete-older-than 30d";
    };

    # Keep build-time dependencies for easier debugging
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
  };
    
    # Allow unfree packages (for things like Discord, Steam, etc.)
  nixpkgs.config.allowUnfree = true;
}
      
    

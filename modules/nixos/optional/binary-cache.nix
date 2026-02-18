{ config, lib, pkgs, ... }:

lib.mkIf config.asthrossystems.features.binaryCache.enable {
  
  # Nix binary cache server
  services.nix-serve = {
    enable = true;
    secretKeyFile = "/var/lib/nix-serve/cache-private-key.pem";
    port = 5000;
    bindAddress = "0.0.0.0";  # Listen on all interfaces
  };
  
  # Open firewall
  networking.firewall.allowedTCPPorts = [ 5000 ];
  
  # Generate cache signing keys on first boot
  systemd.services.nix-serve-keys = {
    description = "Generate nix-serve signing keys";
    wantedBy = [ "multi-user.target" ];
    before = [ "nix-serve.service" ];
    
    script = ''
      mkdir -p /var/lib/nix-serve
      if [ ! -f /var/lib/nix-serve/cache-private-key.pem ]; then
        echo "Generating binary cache signing keys..."
        ${pkgs.nix}/bin/nix-store --generate-binary-cache-key \
          ${config.asthrossystems.features.binaryCache.server} \
          /var/lib/nix-serve/cache-private-key.pem \
          /var/lib/nix-serve/cache-public-key.pem
        
        echo "Public key saved to: /var/lib/nix-serve/cache-public-key.pem"
        echo "You'll need to add this to all client machines!"
      fi
    '';
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}

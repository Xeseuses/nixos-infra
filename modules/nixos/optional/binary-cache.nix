{ config, lib, pkgs, ... }:
lib.mkIf config.asthrossystems.features.binaryCache.enable {
  # Nix binary cache server (harmonia — replaces nix-serve)
  services.harmonia = {
    enable = true;
    signKeyPaths = [ "/var/lib/nix-serve/cache-private-key.pem" ];
    settings = {
      bind = "0.0.0.0:5000";
    };
  };

  # Open firewall (same port as before — no client changes needed)
  networking.firewall.allowedTCPPorts = [ 5000 ];

  # Generate cache signing keys on first boot (kept for new deployments)
  systemd.services.nix-serve-keys = {
    description = "Generate nix-serve signing keys";
    wantedBy = [ "multi-user.target" ];
    before = [ "harmonia.service" ];
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


# hosts/eridanus/wireguard.nix
#
# Eridanus as WireGuard peer — connects to lyra hub.
# Used so lyra's Caddy can proxy to Nextcloud on eridanus.
{ config, ... }:
{
  sops.secrets."eridanus/wireguard/private-key" = {};

  networking.wireguard.interfaces.wg0 = {
    ips        = [ "10.200.0.7/24" ];
    privateKeyFile = config.sops.secrets."eridanus/wireguard/private-key".path;

    peers = [{
      publicKey  = "TPGNC4CP2U75ZMvWW2KP7hba/4RqeDYZZsbmfJPMG1o=";
      allowedIPs = [ "10.200.0.0/24" ];
      endpoint   = "77.42.83.12:51821";
      persistentKeepalive = 25;
    }];
  };

  networking.firewall.trustedInterfaces = [ "wg0" ];
}


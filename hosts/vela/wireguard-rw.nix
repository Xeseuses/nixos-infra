{ config, ... }:
{
  sops.secrets."vela/wireguard/rw-private-key" = {};

  networking.wireguard.interfaces.wg-home = {
    ips = [ "10.200.0.4/24" ];
    privateKeyFile = config.sops.secrets."vela/wireguard/rw-private-key".path;

    peers = [{
      publicKey = "TPGNC4CP2U75ZMvWW2KP7hba/4RqeDYZZsbmfJPMG1o=";
      allowedIPs = [
        "10.200.0.0/24"   # WireGuard subnet
        "10.40.0.0/16"    # full home network
      ];
      endpoint = "77.42.83.12:51821";
      persistentKeepalive = 25;
    }];
  };

  networking.firewall.trustedInterfaces = [ "wg-home" ];
}

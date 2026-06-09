# hosts/orion/wireguard.nix
#
# Orion as WireGuard peer — connects to lyra hub.
# This makes orion the gateway for road warriors to reach home VLANs.
# Much more resilient than routing via andromeda — orion is always on.
#
# Topology after this change:
#   phone/vela → lyra → orion (10.200.0.6) → home VLANs (10.40.0.0/16)
{ config, ... }:
{
  sops.secrets."orion/wireguard/private-key" = {};

  networking.wireguard.interfaces.wg0 = {
    ips        = [ "10.200.0.6/24" ];
    privateKeyFile = config.sops.secrets."orion/wireguard/private-key".path;

    peers = [{
      # lyra — WireGuard hub
      publicKey  = "TPGNC4CP2U75ZMvWW2KP7hba/4RqeDYZZsbmfJPMG1o=";
      allowedIPs = [ "10.200.0.0/24" ];   # only WireGuard subnet via lyra
      endpoint   = "77.42.83.12:51821";
      persistentKeepalive = 25;
    }];

    # No postSetup needed — orion already routes 10.40.0.0/16 natively
    # as it's the router for all VLANs
  };

  # Trust WireGuard interface — road warriors are trusted once on the tunnel
  networking.firewall.trustedInterfaces = [ "wg0" ];
}


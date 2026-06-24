# hosts/norma/wireguard.nix
#
# Norma joins the existing mesh as a peer, following the lyra
# precedent: gets its own WireGuard IP, does NOT receive routes into any
# home VLAN. Internal hosts (orion, eridanus, caelum, andromeda,
# horologium) connect OUTBOUND to Norma's WG IP to ship Wazuh
# agent data — Norma never needs an inbound path into 10.40.0.0/16.
#
# This keeps a compromised Norma in the same limited blast
# radius as a compromised lyra: it can see WireGuard-tunneled agent
# traffic addressed to it, nothing else.

{ config, lib, pkgs, ... }:

{
  sops.secrets."wireguard/norma-private-key" = { };

  networking.wireguard.interfaces.wg-mesh = {
    ips = [ "10.200.0.8/32" ]; # next free slot after eridanus (10.200.0.7)
    privateKeyFile = config.sops.secrets."wireguard/norma-private-key".path;

    peers = [
      {
        # lyra as the mesh hub
        publicKey = "REPLACE_WITH_LYRA_PUBLIC_KEY";
        endpoint = "77.42.83.12:51821";
        allowedIPs = [ "10.200.0.0/24" ]; # mesh subnet only — no VLAN routes
        persistentKeepalive = 25;
      }
    ];
  };

  # On lyra's side (hosts/lyra/wireguard.nix), add the corresponding peer:
  #   {
  #     publicKey = "<norma pubkey>";
  #     allowedIPs = [ "10.200.0.8/32" ];
  #   }
  # Deliberately no entry granting Norma routes to 10.40.0.0/16
  # anywhere in the mesh — same omission pattern as andromeda/caelum/eridanus.
}


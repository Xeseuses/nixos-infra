{ config, pkgs, ... }:
{
  # ── Mullvad WireGuard VPN ─────────────────────────────────────────────────
  # Routes VLANs 10/20/30/50 through Mullvad. VLAN 40 (Servers) bypasses VPN
  # to keep WireGuard tunnels to lyra stable.
  # Kill switch: if mullvad0 goes down, affected VLANs lose internet (no leak).

  networking.wireguard.interfaces.mullvad0 = {
    ips = [ "10.75.35.38/32" ];
    privateKeyFile = "/var/lib/wireguard/mullvad.key";

    peers = [{
      publicKey = "PJvsgLogdAgZiVSxwTDyk9ri02mLZGuElklHShIjDGM=";
      endpoint = "154.47.29.2:51820";
      allowedIPs = [ "0.0.0.0/0" ];
      persistentKeepalive = 25;
    }];

    # Route VLANs 10/20/30/50 through mullvad0 instead of enp1s0
    postSetup = ''
      # Create a separate routing table for VPN traffic
      ${pkgs.iproute2}/bin/ip route add default dev mullvad0 table 100
      ${pkgs.iproute2}/bin/ip rule add from 10.40.10.0/24 lookup 100 priority 100
      ${pkgs.iproute2}/bin/ip rule add from 10.40.20.0/24 lookup 100 priority 100
      ${pkgs.iproute2}/bin/ip rule add from 10.40.30.0/24 lookup 100 priority 100
      ${pkgs.iproute2}/bin/ip rule add from 10.40.50.0/24 lookup 100 priority 100
    '';

    postShutdown = ''
      ${pkgs.iproute2}/bin/ip route del default dev mullvad0 table 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del from 10.40.10.0/24 lookup 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del from 10.40.20.0/24 lookup 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del from 10.40.30.0/24 lookup 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del from 10.40.50.0/24 lookup 100 2>/dev/null || true
    '';
  };

  # Kill switch: block VPN VLANs from using enp1s0 directly
  # If mullvad0 is down, traffic hits this rule and is dropped
  networking.nftables.tables.mullvad-killswitch = {
    family = "ip";
    content = ''
      chain killswitch {
        type filter hook forward priority -1; policy accept;
        # Block VPN VLANs from exiting via WAN directly (forces VPN or drop)
        iifname { "vlan10", "vlan20", "vlan30", "vlan50" } oifname "enp1s0" drop
      }
    '';
  };

  # NAT for mullvad0 — masquerade VPN VLAN traffic behind Mullvad IP
  networking.nftables.tables.mullvad-nat = {
    family = "ip";
    content = ''
      chain mullvad-postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        iifname { "vlan10", "vlan20", "vlan30", "vlan50" } oifname "mullvad0" masquerade
      }
    '';
  };
}


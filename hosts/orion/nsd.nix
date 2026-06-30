# hosts/orion/nsd.nix
#
# NSD: authoritative DNS for two zones:
#   1. lan.      — all internal hostnames
#   2. xesh.cc.  — split-horizon: internal clients get LAN IPs directly
#
# NSD listens only on 127.0.0.1:5354
# Unbound has stub-zones pointing to it
# Clients never talk to NSD directly

{ ... }:

{
  services.nsd = {
    enable     = true;
    interfaces = [ "127.0.0.1" ];
    port       = 5354;

    zones = {

      # ── lan. zone ─────────────────────────────────────────────────────────
      "lan." = {
        data = ''
          $ORIGIN lan.
          $TTL 300

          @   IN SOA  orion.lan. hostmaster.lan. (
                      2026060605  ; serial
                      3600        ; refresh
                      900         ; retry
                      604800      ; expire
                      300 )       ; minimum TTL

          @           IN NS   orion.lan.

          ; ── Router ────────────────────────────────────────────────────
          orion       IN A    10.40.10.1

          ; ── Lan ────────────────────────────────────────────────────
          vela        IN A    10.40.10.106
          vega        IN A    10.40.10.109

          ; ── Servers (VLAN40) ──────────────────────────────────────────
          caelum      IN A    10.40.40.101
          andromeda   IN A    10.40.40.104
          eridanus    IN A    10.40.40.117
          cache       IN A    10.40.40.117
          horologium  IN A    10.40.40.106
          ha          IN A    10.40.40.115

          ;-- Services --
          security    IN A    10.40.40.117

          ; ── Management (VLAN30) ───────────────────────────────────────
          unifi-ap    IN A    10.40.30.120

          ; ── IoT (VLAN50) ──────────────────────────────────────────────
          everything-presence  IN A    10.40.50.100
          bed-presence         IN A    10.40.50.101
          aqara-hub            IN A    10.40.50.103
        '';
      };

      # ── Reverse zone for VLAN40 (servers) ─────────────────────────────────
      "40.40.10.in-addr.arpa." = {
        data = ''
          $ORIGIN 40.40.10.in-addr.arpa.
          $TTL 300

          @   IN SOA  orion.lan. hostmaster.lan. (
                      2026060603 3600 900 604800 300 )
          @   IN NS   orion.lan.

          101 IN PTR  caelum.lan.
          104 IN PTR  andromeda.lan.
          106 IN PTR  horologium.lan.
          115 IN PTR  ha.lan.
          117 IN PTR  eridanus.lan.
        '';
      };

      # ── Reverse zone for VLAN10 (LAN) ─────────────────────────────────────
      "10.40.10.in-addr.arpa." = {
        data = ''
          $ORIGIN 10.40.10.in-addr.arpa.
          $TTL 300

          @   IN SOA  orion.lan. hostmaster.lan. (
                      2026060603 3600 900 604800 300 )
          @   IN NS   orion.lan.

          1   IN PTR  orion.lan.
        '';
      };

      # ── xesh.cc split-horizon zone ─────────────────────────────────────────
      # Internal clients resolve xesh.cc subdomains to LAN IPs directly
      # where possible. Services without a local reverse proxy go via VPS.
      # External clients get the public IP from Porkbun as normal.
      "xesh.cc." = {
        data = ''
          $ORIGIN xesh.cc.
          $TTL 300

          @   IN SOA  orion.lan. hostmaster.xesh.cc. (
                      2026060607  ; serial — moved search.xesh.cc to the
                                  ; via-VPS-proxy group (June 30, second fix —
                                  ; direct-to-caelum was wrong, see note below)
                      3600        ; refresh
                      900         ; retry
                      604800      ; expire
                      300 )       ; minimum

          @           IN NS   orion.lan.

          orion        IN A    10.40.10.1

          ; ── Via VPS proxy (TLS termination on VPS) ──────────────────────
          ha           IN A    77.42.83.12
          immich       IN A    77.42.83.12
          cloud        IN A    77.42.83.12
          search       IN A    77.42.83.12

          ; ── Direct LAN access ───────────────────────────────────────────
          ; Services hosted on caelum (10.40.40.101) that internal clients
          ; can reach directly, bypassing lyra entirely.
          ;
          ; search.xesh.cc was ORIGINALLY added here (June 30), pointing
          ; directly at caelum — this was WRONG and has been moved above,
          ; to the via-VPS-proxy group instead. SearXNG's NixOS service is
          ; deliberately bound only to caelum's WireGuard interface
          ; (10.200.0.3:8888), not its LAN interface — unlike
          ; audiobooks/solibieb, which DO have something listening on
          ; caelum's LAN IP directly. Pointing search.xesh.cc at
          ; 10.40.40.101 produced a connection timeout (port 8888 was
          ; never open or listening on the LAN interface at all), and even
          ; if it had connected, it would have been a second, separate,
          ; uncertified HTTP path inconsistent with how ha/immich/cloud
          ; behave. Routing through lyra instead means search.xesh.cc now
          ; works identically at home and away — same HTTPS cert, same
          ; Caddy vhost, same WireGuard tunnel hop already used for the
          ; external path, with no second access pattern to maintain.
          audiobooks   IN A    10.40.40.101
          solibieb     IN A    10.40.40.101

          threats      IN A    10.200.0.1

        '';
      };
    };
  };
}


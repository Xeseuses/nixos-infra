# hosts/orion/unbound.nix
#
# Unbound is now the middle layer: port 5335, localhost only.
# AGH → Unbound :5335 → NSD :5354 (for .lan and xesh.cc)
#                      → Quad9 DoT (for everything else)
#
# StevenBlack systemd timer removed — AGH handles blocklists now.
{ pkgs, ... }:
{
  services.unbound = {
    enable = true;
    settings = {

      server = {
        # Localhost only — AGH is the only thing that talks to Unbound
        interface = [ "127.0.0.1" ];
        port      = 5335;

        do-ip4 = true;
        do-ip6 = true;
        do-udp = true;
        do-tcp = true;

        # Only AGH on localhost can query Unbound
        access-control = [
          "0.0.0.0/0 refuse"
          "127.0.0.0/8 allow"
        ];

        # Performance & security
        num-threads            = 2;
        cache-min-ttl          = 300;
        cache-max-ttl          = 86400;
        hide-identity          = true;
        hide-version           = true;
        harden-glue            = true;
        harden-dnssec-stripped = true;
        use-caps-for-id        = false;
        prefetch               = true;
        prefetch-key           = true;

        # DNSSEC validation
        auto-trust-anchor-file = "/var/lib/unbound/root.key";
   
        domain-insecure = [
    	  "lan."
	  "xesh.cc."
	  "40.40.40.in-addr.arpa."
  	  "10.40.10.in-addr.arpa."
	 ];
      };

      # ── Stub zones → NSD ────────────────────────────────────────────────
      # For .lan and xesh.cc, Unbound delegates to NSD instead of recursing.
      stub-zone = [
        {
          name      = "lan.";
          stub-addr = "127.0.0.1@5354";
        }
        {
          name      = "xesh.cc.";
          stub-addr = "127.0.0.1@5354";
        }
        {
          name      = "40.40.40.in-addr.arpa.";
          stub-addr = "127.0.0.1@5354";
        }
        {
          name      = "10.40.10.in-addr.arpa.";
          stub-addr = "127.0.0.1@5354";
        }
      ];

      # ── Upstream: Quad9 over DoT ─────────────────────────────────────────
      forward-zone = [
        {
          name                 = ".";
          forward-tls-upstream = true;
          forward-addr = [
            "9.9.9.9@853#dns.quad9.net"
            "149.112.112.112@853#dns.quad9.net"
          ];
        }
      ];
    };
  };

  # Unbound is localhost-only — no per-interface firewall rules needed.
  # Port 53 on VLAN interfaces is handled by AGH.
}


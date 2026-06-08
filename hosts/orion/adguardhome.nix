# hosts/orion/adguardhome.nix
#
# Adguardhome sits on port 53 on all trusted VLAN IPs.
# It forwards clean queries upstream to Unbound on 127.0.0.1:5335.
# Unbound handles DoT to Quad9 + DNSSEC + NSD stub zones.
#
# Clients see no change — Kea still hands out 10.40.x.1 as DNS.
# VLAN20 (guests) gets adblocking too but no .lan resolution.
# VLAN60 (Tor) is intentionally excluded — Tor clients use Tor DNS.
{ config, ... }:
{
  services.adguardhome = {
    enable = true;
    mutableSettings = false;

    settings = {
      # ── Web UI ──────────────────────────────────────────────────────────
      http = {
        address    = "0.0.0.0:3000";
        session_ttl = "720h";
      };

      # ── DNS ─────────────────────────────────────────────────────────────
      dns = {
        bind_hosts = [
	  "127.0.0.1"
          "10.40.10.1"   # LAN
          "10.40.20.1"   # Guest — adblocking, no .lan
          "10.40.30.1"   # Management
          "10.40.40.1"   # Servers
          "10.40.50.1"   # IoT
          # 10.40.60.1 intentionally excluded — Tor VLAN
        ];
        port = 53;

        upstream_dns  = [ "127.0.0.1:5335" ];
        bootstrap_dns = [ "9.9.9.9" "149.112.112.112" ];
        upstream_mode = "load_balance";
        fallback_dns = [ "127.0.0.1:5335" ];

        # ── Blocklists ────────────────────────────────────────────────────
        filters = [
          {
            enabled = true;
            id      = 1;
            name    = "AdGuard DNS filter";
            url     = "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt";
          }
          {
            enabled = true;
            id      = 2;
            name    = "Steven Black unified hosts";
            url     = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          }
          {
            enabled = true;
            id      = 3;
            name    = "OISD full";
            url     = "https://big.oisd.nl/domainswild";
          }
        ];

        filtering_enabled       = true;
        filters_update_interval = 24;
        blocked_response_ttl    = 10;
        protection_enabled      = true;

        cache_size       = 4194304;
        cache_ttl_min    = 0;
        cache_ttl_max    = 0;
        cache_optimistic = true;

        ratelimit = 0;
        ratelimit_whitelist = [
        ];
      };

      # ── Query log ────────────────────────────────────────────────────────
      querylog = {
        enabled      = true;
        file_enabled = true;
        interval     = "168h";
        size_memory  = 1000;
        ignored      = [];
      };

      # ── Statistics ───────────────────────────────────────────────────────
      statistics = {
        enabled  = true;
        interval = "168h";
      };

      # ── Auth ─────────────────────────────────────────────────────────────
      # Generate with: nix shell nixpkgs#python3Packages.bcrypt --command python3 -c
      #   "import bcrypt; print(bcrypt.hashpw(b'yourpassword', bcrypt.gensalt(10)).decode())"
      users = [
        {
          name     = "admin";
          password = "$2b$10$kT/QVtKv5IUYDHoZx7Ug2OarDmCEl9DqSDXX8PpRQaUYIpwqDUTra";
        }
      ];

      schema_version = 32;
    };
  };

  # ── Firewall ───────────────────────────────────────────────────────────────
  # Port 3000 (web UI) — LAN, Management, Servers only
  networking.firewall.interfaces = {
    vlan10 = { allowedTCPPorts = [ 3000 ]; };
    vlan30 = { allowedTCPPorts = [ 3000 ]; };
    vlan40 = { allowedTCPPorts = [ 3000 ]; };
  };
}


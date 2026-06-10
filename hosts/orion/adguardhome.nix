# hosts/orion/adguardhome.nix
#
# Adguardhome — DNS frontend on port 53.
# AGH → Unbound :5335 → NSD :5354 (lan. + xesh.cc) / Quad9 DoT (external)
#
# Client groups:
#   servers  — VLAN40: relaxed blocking, no safe search
#   iot      — VLAN50: strict blocking, no safe search (breaks some devices)
#   trusted  — LAN/Management: standard blocking
#   guest    — VLAN20: standard blocking, no .lan access (handled by DNS)
{ config, ... }:
{
  services.adguardhome = {
    enable = true;
    mutableSettings = false;

    settings = {
      # ── Web UI ────────────────────────────────────────────────────────────
      http = {
        address     = "0.0.0.0:3000";
        session_ttl = "720h";
      };

      # ── DNS ───────────────────────────────────────────────────────────────
      dns = {
        bind_hosts = [
          "127.0.0.1"
          "10.40.10.1"   # LAN
          "10.40.20.1"   # Guest
          "10.40.30.1"   # Management
          "10.40.40.1"   # Servers
          "10.40.50.1"   # IoT
        ];
        port = 53;

        upstream_dns  = [ "127.0.0.1:5335" ];
        bootstrap_dns = [ "9.9.9.9" "149.112.112.112" ];
        upstream_mode = "load_balance";
        fallback_dns  = [ "127.0.0.1:5335" ];

        use_private_ptr_resolvers = true;
        local_ptr_upstreams       = [ "127.0.0.1:5335" ];
        private_networks = [
          "10.40.10.0/24"
          "10.40.40.0/24"
        ];

        # DNSSEC validation (Unbound also validates — double protection)
        enable_dnssec = true;

        # Larger cache — 32MB instead of 4MB
        cache_size       = 33554432;
        cache_ttl_min    = 0;
        cache_ttl_max    = 0;
        cache_optimistic = true;

        ratelimit           = 0;
        ratelimit_whitelist = [];

        # ── Blocklists ──────────────────────────────────────────────────────
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
          {
            enabled = true;
            id      = 4;
            name    = "HaGeZi Pro++";
            url     = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt";
          }
        ];

        filtering_enabled       = true;
        filters_update_interval = 24;
        blocked_response_ttl    = 10;
        protection_enabled      = true;
      };

      # ── Named clients ──────────────────────────────────────────────────────
      # Gives devices readable names in query log + enables per-client rules.
      # Use MAC addresses for stable identification (IPs can change).
      clients = {
        persistent = [
          # ── LAN (VLAN10) ─────────────────────────────────────────────────
          {
            name            = "vela";
            ids             = [ "f0:57:a6:66:3e:b0" ];
            use_global_settings       = true;
            use_global_blocked_services = true;
          }
          {
            name            = "vega";
            ids             = [ "dc:45:46:95:a2:c2" ];
            use_global_settings       = true;
            use_global_blocked_services = true;
          }
          {
            name            = "phone";
            ids             = [ "e2:89:b2:85:c7:10" ];
            use_global_settings       = true;
            use_global_blocked_services = true;
          }

          # ── Management (VLAN30) ───────────────────────────────────────────
          {
            name            = "unifi-ap";
            ids             = [ "f4:e2:c6:20:08:d6" ];
            use_global_settings       = true;
            use_global_blocked_services = true;
          }

          # ── Servers (VLAN40) — relaxed: no blocking ───────────────────────
          {
            name                      = "caelum";
            ids                       = [ "7c:83:34:b9:7c:04" ];
            use_global_settings       = false;
            filtering_enabled         = false;   # servers need unrestricted DNS
            use_global_blocked_services = false;
          }
          {
            name                      = "andromeda";
            ids                       = [ "e8:ff:1e:d2:b0:2f" ];
            use_global_settings       = false;
            filtering_enabled         = false;
            use_global_blocked_services = false;
          }
          {
            name                      = "horologium";
            ids                       = [ "c8:7f:54:6b:c3:da" ];
            use_global_settings       = false;
            filtering_enabled         = false;
            use_global_blocked_services = false;
          }
          {
            name                      = "eridanus";
            ids                       = [ "7c:83:34:b9:b8:51" ];
            use_global_settings       = false;
            filtering_enabled         = false;
            use_global_blocked_services = false;
          }
          {
            name                      = "homeassistant";
            ids                       = [ "52:54:00:f6:33:94" ];
            use_global_settings       = false;
            filtering_enabled         = false;
            use_global_blocked_services = false;
          }

          # ── IoT (VLAN50) — strict blocking ────────────────────────────────
          {
            name                      = "everything-presence";
            ids                       = [ "08:a6:f7:93:66:ec" ];
            use_global_settings       = true;
            use_global_blocked_services = true;
          }
          {
            name                      = "bed-presence";
            ids                       = [ "b0:81:84:2b:d8:9c" ];
            use_global_settings       = true;
            use_global_blocked_services = true;
          }
          {
            name                      = "aqara-hub";
            ids                       = [ "54:ef:44:6e:6f:b0" ];
            use_global_settings       = true;
            use_global_blocked_services = true;
          }
          {
            name                      = "aqara-fp2";
            ids                       = [ "54:ef:44:4e:11:09" ];
            use_global_settings       = true;
            use_global_blocked_services = true;
          }
          {
            name                      = "reolink-doorbell";
            ids                       = [ "48:9e:9d:0e:2a:17" ];
            use_global_settings       = false;
            filtering_enabled         = true;
            # Reolink needs its cloud to function — allow it but still block ads
            use_global_blocked_services = false;
          }
        ];
      };

      # ── Query log ──────────────────────────────────────────────────────────
      querylog = {
        enabled      = true;
        file_enabled = true;
        interval     = "720h";   # 30 days
        size_memory  = 2000;
        ignored      = [];
      };

      # ── Statistics ─────────────────────────────────────────────────────────
      statistics = {
        enabled  = true;
        interval = "720h";   # 30 days — better trend visibility
      };

      # ── Auth ───────────────────────────────────────────────────────────────
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
  networking.firewall.interfaces = {
    vlan10 = { allowedTCPPorts = [ 3000 ]; };
    vlan30 = { allowedTCPPorts = [ 3000 ]; };
    vlan40 = { allowedTCPPorts = [ 3000 ]; };
  };
}


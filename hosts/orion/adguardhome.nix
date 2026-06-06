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

    # mutableSettings = false means AGH won't write back to its config file.
    # All config lives here in Nix. Allowlist/blocklist changes go here too.
    mutableSettings = false;

    settings = {
      # ── Web UI ────────────────────────────────────────────────────────────
      http = {
        address = "0.0.0.0:3000";   # firewall below restricts who can reach it
        session_ttl = "720h";
      };

      # ── DNS ───────────────────────────────────────────────────────────────
      dns = {
        # Bind on all VLAN gateway IPs except VLAN60 (Tor) and VLAN20 gateway
        # VLAN20 guests get adblocking via 10.40.20.1 too
        bind_hosts = [
          "10.40.10.1"   # LAN
          "10.40.20.1"   # Guest — adblocking but no .lan
          "10.40.30.1"   # Management
          "10.40.40.1"   # Servers
          "10.40.50.1"   # IoT
          # 10.40.60.1 intentionally excluded — Tor VLAN uses Tor DNS
        ];
        port = 53;

        # Upstream: Unbound on localhost (handles DoT, DNSSEC, NSD stubs)
        upstream_dns = [ "127.0.0.1:5335" ];
        bootstrap_dns = [ "9.9.9.9" "149.112.112.112" ];
        upstream_mode = "parallel";

        # Fallback if upstream is unreachable
        fallback_dns = [ "9.9.9.9" "149.112.112.112" ];

        # ── Blocklists ─────────────────────────────────────────────────────
        # Replaces the StevenBlack systemd timer in unbound.nix
        # AGH downloads and updates these automatically
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

        filtering_enabled         = true;
        filters_update_interval   = 24;   # hours
        blocked_response_ttl      = 10;
        protection_enabled        = true;

        # Cache — AGH has its own cache layer on top of Unbound's
        cache_size              = 4194304;   # 4MB
        cache_ttl_min           = 0;
        cache_ttl_max           = 0;         # respect upstream TTL
        cache_optimistic        = true;

        # Privacy
        ratelimit               = 20;        # queries/sec per client — protects against floods
        ratelimit_whitelist     = [
          "10.40.10.0/24"
          "10.40.30.0/24"
          "10.40.40.0/24"
        ];

        # AAAA blocking for IoT VLAN (many IoT devices handle IPv6 poorly)
        # aaaa_disabled = false;   # uncomment to block AAAA on all clients
      };

      # ── Query log ─────────────────────────────────────────────────────────
      querylog = {
        enabled          = true;
        file_enabled     = true;
        interval         = "168h";   # 7 days
        size_memory      = 1000;
        ignored          = [];
      };

      # ── Statistics ────────────────────────────────────────────────────────
      statistics = {
        enabled  = true;
        interval = "168h";   # 7 days
      };

      # ── User/auth ─────────────────────────────────────────────────────────
      # Set a real password hash here. Generate with:
      #   htpasswd -bnBC 10 "" yourpassword | tr -d ':\n'
      # For now using a placeholder — change before deploying!
      users = [
        {
          name           = "admin";
          password       = "$2y$10$PLACEHOLDER_REPLACE_WITH_REAL_BCRYPT_HASH";
        }
      ];

      # ── Schema version ────────────────────────────────────────────────────
      schema_version = 28;
    };
  };

  # ── Firewall ──────────────────────────────────────────────────────────────
  # DNS (53) is already open per-interface in default.nix firewall block.
  # Web UI (3000) is only for trusted VLANs and wg0 — not guests or IoT.
  networking.firewall.interfaces = {
    vlan10 = { allowedTCPPorts = [ 3000 ]; };
    vlan30 = { allowedTCPPorts = [ 3000 ]; };
    vlan40 = { allowedTCPPorts = [ 3000 ]; };
  };

  # ── Impermanence ──────────────────────────────────────────────────────────
  # AGH stores its query log, stats DB, and filter cache here.
  # Must persist across reboots or you lose all history and filters reset.
  environment.persistence."/persist".directories = [
    "/var/lib/adguardhome"
  ];
}


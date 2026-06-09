# hosts/lyra/dashboard.nix
#
# Threat dashboard for lyra.
# Generates static HTML every 5 minutes from endlessh + honeypot logs + CrowdSec.
# Served by Caddy on threats.xesh.cc — only accessible via WireGuard (10.200.x.x).
{ config, pkgs, ... }:
let
  dashboardScript = pkgs.writeScript "generate-dashboard" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./generate-dashboard.py}
  '';
in
{
  # ── Dashboard generator script ────────────────────────────────────────────
  # Runs every 5 minutes via systemd timer
  systemd.services.honeypot-dashboard = {
    description = "Generate honeypot threat dashboard";
    serviceConfig = {
      Type            = "oneshot";
      ExecStart       = dashboardScript;
      # Needs access to journalctl and cscli
      SupplementaryGroups = [ "systemd-journal" ];
    };
  };

  systemd.timers.honeypot-dashboard = {
    description  = "Regenerate honeypot dashboard every 5 minutes";
    wantedBy     = [ "timers.target" ];
    timerConfig  = {
      OnBootSec         = "1min";
      OnUnitActiveSec   = "5min";
      Persistent        = true;
    };
  };

  # ── Caddy vhost — WireGuard only ──────────────────────────────────────────
  # threats.xesh.cc only resolves to 10.200.0.1 internally (via NSD on orion)
  # Add to NSD xesh.cc zone: threats IN A 10.200.0.1
  services.caddy.virtualHosts."http://threats.xesh.cc" = {
    extraConfig = ''
      root * /var/lib/honeypot-dashboard
      file_server
      # Only allow WireGuard clients
      @blocked not remote_ip 10.200.0.0/24 10.40.0.0/16
      abort @blocked
    '';
  };

  # ── Dashboard directory ───────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d /var/lib/honeypot-dashboard 0755 root root -"
  ];
}


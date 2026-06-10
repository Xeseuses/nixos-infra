# hosts/lyra/dashboard.nix
#
# Threat dashboard for lyra.
# Generates static HTML every 5 minutes from endlessh + honeypot logs + CrowdSec.
# Served by Caddy on threats.xesh.cc — accessible from WireGuard + home VLANs.
{ config, pkgs, ... }:
let
  dashboardScript = pkgs.writeScript "generate-dashboard" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./generate-dashboard.py}
  '';
in
{
  systemd.services.honeypot-dashboard = {
    description = "Generate honeypot threat dashboard";
    serviceConfig = {
      Type            = "oneshot";
      ExecStart       = dashboardScript;
      SupplementaryGroups = [ "systemd-journal" ];
    };
    # ── Critical: add cscli and journalctl to PATH ────────────────────────
    path = with pkgs; [
      crowdsec          # provides cscli for banning
      systemd           # provides journalctl for endlessh logs
    ];
  };

  systemd.timers.honeypot-dashboard = {
    description = "Regenerate honeypot dashboard every 5 minutes";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "1min";
      OnUnitActiveSec = "5min";
      Persistent      = true;
    };
  };

  services.caddy.virtualHosts."http://threats.xesh.cc" = {
    extraConfig = ''
      root * /var/lib/honeypot-dashboard
      file_server
      @blocked not remote_ip 10.200.0.0/24 10.40.0.0/16
      abort @blocked
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/honeypot-dashboard 0755 root root -"
  ];
}


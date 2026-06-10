# hosts/eridanus/security-dashboard.nix
#
# Security monitoring dashboard — aggregates auditd + aide data from all hosts.
# Runs every 15 minutes via systemd timer.
# Served by nginx on security.lan (internal only, WireGuard accessible).
{ config, pkgs, ... }:
let
  # Hosts to monitor — must be reachable via SSH from eridanus
  # eridanus monitors itself locally (no SSH needed)
  monitoredHosts = [
    { name = "orion";       ip = "10.40.10.1";   }
    { name = "caelum";      ip = "10.40.40.101";  }
    { name = "andromeda";   ip = "10.40.40.104";  }
    { name = "horologium";  ip = "10.40.40.106";  }
    { name = "lyra";        ip = "77.42.83.12";   sshPort = 22022; }
  ];

  dashboardScript = pkgs.writeScript "generate-security-dashboard" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./generate-security-dashboard.py}
  '';
in
{
  # ── SSH key for monitoring ────────────────────────────────────────────────
  # eridanus needs passwordless SSH to all monitored hosts
  # The root user's SSH key must be in authorizedKeys on each host
  # Generate with: ssh-keygen -t ed25519 -f /persist/etc/ssh/monitor_key -N ""
  # Then add the public key to each host's authorizedKeys

  # ── Dashboard generator ────────────────────────────────────────────────────
  systemd.services.security-dashboard = {
    description = "Generate security monitoring dashboard";
    after       = [ "network.target" ];
    path = with pkgs; [
      openssh        # for ssh commands to remote hosts
      audit          # for aureport/ausearch
      aide           # for local aide checks
      coreutils
      gnugrep
    ];
    serviceConfig = {
      Type            = "oneshot";
      ExecStart       = dashboardScript;
      # Run as root to access audit logs
    };
    environment = {
      HOME           = "/root";
      SSH_OPTIONS    = "-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes";
    };
  };

  systemd.timers.security-dashboard = {
    description = "Regenerate security dashboard every 15 minutes";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "2min";
      OnUnitActiveSec = "15min";
      Persistent      = true;
    };
  };

  # ── nginx vhost ────────────────────────────────────────────────────────────
  # Accessible at http://security.lan or http://10.40.40.117:8090
  # Add security.lan to NSD lan. zone pointing to 10.40.40.117
  services.nginx.virtualHosts."security.lan" = {
    listen = [{ addr = "0.0.0.0"; port = 8090; }];
    locations."/" = {
      root = "/var/lib/security-dashboard";
      tryFiles = "$uri $uri/ /index.html";
      extraConfig = ''
        add_header Cache-Control "no-cache, no-store, must-revalidate";
      '';
    };
  };

  # Open port 8090 on trusted interfaces only
  networking.firewall.interfaces.enp1s0.allowedTCPPorts = [ 8090 ];

  # ── Dashboard directory ────────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d /var/lib/security-dashboard 0755 root root -"
  ];

  # ── Impermanence ──────────────────────────────────────────────────────────
  environment.persistence."/persist".directories = [
    "/var/lib/security-dashboard"
  ];
}


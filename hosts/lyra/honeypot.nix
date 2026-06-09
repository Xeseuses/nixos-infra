# hosts/lyra/honeypot.nix
#
# Honeypot stack for lyra:
#   port 22    → endlessh-go (SSH tarpit)
#   port 22022 → real sshd
#   port 21    → fake FTP
#   port 23    → fake telnet
#   port 3306  → fake MySQL
#   port 8080  → fake HTTP
{ config, pkgs, lib, ... }:
let
  # Python-based fake service — logs IP and sends a banner, then closes
  fakeService = { name, port, banner }: {
    description = "Honeypot: fake ${name} on port ${toString port}";
    after       = [ "network.target" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      Type       = "simple";
      Restart    = "always";
      RestartSec = "2s";
      ExecStart  = pkgs.writeScript "honeypot-${name}" ''
        #!${pkgs.python3}/bin/python3
        import socket, datetime, os

        LOG = "/var/log/honeypot/${name}.log"
        os.makedirs("/var/log/honeypot", exist_ok=True)

        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", ${toString port}))
        srv.listen(50)

        while True:
            try:
                conn, addr = srv.accept()
                ip = addr[0]
                ts = datetime.datetime.now().isoformat()
                with open(LOG, "a") as f:
                    f.write(f"{ts} honeypot_${name} src_ip={ip}\n")
                try:
                    conn.sendall(b"${banner}\r\n")
                except:
                    pass
                conn.close()
            except Exception as e:
                pass
      '';
    };
  };
in
{
  # ── Move real SSH to port 22022 ────────────────────────────────────────
  services.openssh = {
    enable   = true;
    ports    = [ 22022 ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin        = lib.mkForce "no";
    };
  };

  # ── endlessh-go — SSH tarpit on port 22 ───────────────────────────────
  services.endlessh-go = {
    enable       = true;
    port         = 22;
    extraOptions = [ "-logtostderr" "-v=1" ];
  };

  # ── Fake service honeypots ─────────────────────────────────────────────
  systemd.services.honeypot-ftp    = fakeService { name = "ftp";    port = 21;   banner = "220 FTP server ready."; };
  systemd.services.honeypot-telnet = fakeService { name = "telnet"; port = 23;   banner = "Ubuntu 22.04 LTS login:"; };
  systemd.services.honeypot-mysql  = fakeService { name = "mysql";  port = 3306; banner = "Host is not allowed to connect"; };
  systemd.services.honeypot-http   = fakeService { name = "http";   port = 8080; banner = "HTTP/1.1 200 OK\r\nContent-Length: 0"; };

  # ── Log rotation ───────────────────────────────────────────────────────
  services.logrotate.settings."/var/log/honeypot/*.log" = {
    rotate     = 7;
    daily      = true;
    compress   = true;
    missingok  = true;
    notifempty = true;
  };

  # ── Firewall ───────────────────────────────────────────────────────────
  networking.firewall.allowedTCPPorts = [
    22      # endlessh tarpit
    22022   # real SSH
    21      # fake FTP
    23      # fake telnet
    3306    # fake MySQL
    8080    # fake HTTP
  ];
}


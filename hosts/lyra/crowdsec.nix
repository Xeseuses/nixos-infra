{ config, pkgs, lib, ... }:

{
  services.crowdsec = {
    enable = true;
    allowLocalJournalAccess = true;
    settings = {
      lapi = {
        listen_uri = "127.0.0.1:8080";
      };
    };
    localConfig = {
      acquisitions = [
        {
          filenames = [ "/var/log/auth.log" ];
          labels.type = "syslog";
        }
        {
          filenames = [ "/var/log/caddy/access.log" ];
          labels.type = "caddy";
        }
      ];
    };
  };

  services.crowdsec-firewall-bouncer = {
    enable = true;
    settings = {
      mode = "nftables";
      nftables = {
        ipv4 = {
          enabled = true;
          set-only = false;
          table = "crowdsec";
          chain = "crowdsec-chain";
        };
        ipv6 = {
          enabled = true;
          set-only = false;
          table = "crowdsec6";
          chain = "crowdsec6-chain";
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
  ];
}

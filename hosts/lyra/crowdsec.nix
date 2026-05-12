{ config, pkgs, ... }:

{
  services.crowdsec = {
    enable = true;
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
    settings = {
      api.server = {
        listen_uri = "127.0.0.1:8080";
      };
    };
  };

  # Firewall bouncer — translates CrowdSec decisions to nftables blocks
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
}

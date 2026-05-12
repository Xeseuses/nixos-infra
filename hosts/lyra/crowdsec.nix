{ config, pkgs, lib, ... }:

{
  systemd.tmpfiles.rules = [
    "d /var/lib/crowdsec 0755 crowdsec crowdsec - -"
    "f /var/lib/crowdsec/online_api_credentials.yaml 0750 crowdsec crowdsec - -"
    "d /var/log/caddy 0750 caddy caddy -"
  ];

  sops.secrets."lyra/crowdsec/enroll-key" = {
    owner = "crowdsec";
  };

   services.crowdsec = {
    enable = true;
    settings = {
      general.api.server.enable = true;
      lapi.credentialsFile = "/var/lib/crowdsec/local_api_credentials.yaml";
      capi.credentialsFile = "/var/lib/crowdsec/online_api_credentials.yaml";
      console = {
        tokenFile = config.sops.secrets."lyra/crowdsec/enroll-key".path;
        configuration = {
          share_manual_decisions = true;
          share_tainted = true;
          share_custom = true;
          console_management = false;
          share_context = true;
        };
      };
    };
    localConfig = {
  acquisitions = [
    {
      source = "journalctl";
      journalctl_filter = [
        "_SYSTEMD_UNIT=sshd.service"
        "_SYSTEMD_UNIT=sshd-session.service"
      ];
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
    registerBouncer.enable = true;
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

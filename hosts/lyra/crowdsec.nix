# hosts/lyra/crowdsec.nix
{ config, pkgs, lib, ... }:
{
  systemd.tmpfiles.rules = [
    "d /var/lib/crowdsec 0755 crowdsec crowdsec - -"
    "f /var/lib/crowdsec/online_api_credentials.yaml 0750 crowdsec crowdsec - -"
    "d /var/log/caddy 0750 caddy caddy -"
    "d /var/log/honeypot 0755 root root - -"    # honeypot log dir
  ];

  sops.secrets."lyra/crowdsec/enroll-key" = {
    owner = "crowdsec";
  };

  services.crowdsec = {
    enable = true;
    settings = {
      general.api.server.enable = true;
      lapi.credentialsFile  = "/var/lib/crowdsec/local_api_credentials.yaml";
      capi.credentialsFile  = "/var/lib/crowdsec/online_api_credentials.yaml";
      console = {
        tokenFile = config.sops.secrets."lyra/crowdsec/enroll-key".path;
        configuration = {
          share_manual_decisions = true;
          share_tainted          = true;
          share_custom           = true;
          console_management     = false;
          share_context          = true;
        };
      };
    };

    localConfig = {
      acquisitions = [
        # ── Existing sources ──────────────────────────────────────────────
        {
          source = "journalctl";
          journalctl_filter = [ "SYSLOG_IDENTIFIER=sshd" ];
          labels.type = "syslog";
        }
        {
          source = "journalctl";
          journalctl_filter = [ "SYSLOG_IDENTIFIER=sshd-session" ];
          labels.type = "syslog";
        }
        {
          filenames    = [ "/var/log/caddy/access.log" ];
          labels.type  = "caddy";
        }

        # ── endlessh — SSH tarpit ─────────────────────────────────────────
        # endlessh-go logs to journald as "endlessh-go"
        {
          source = "journalctl";
          journalctl_filter = [ "SYSLOG_IDENTIFIER=endlessh-go" ];
          labels.type = "endlessh";
        }

        # ── Honeypot fake services ────────────────────────────────────────
        {
          filenames   = [ "/var/log/honeypot/ftp.log" ];
          labels.type = "honeypot";
        }
        {
          filenames   = [ "/var/log/honeypot/telnet.log" ];
          labels.type = "honeypot";
        }
        {
          filenames   = [ "/var/log/honeypot/mysql.log" ];
          labels.type = "honeypot";
        }
        {
          filenames   = [ "/var/log/honeypot/http.log" ];
          labels.type = "honeypot";
        }
      ];
    };
  };

  # ── CrowdSec custom parsers ───────────────────────────────────────────────
  # Parser for honeypot log format:
  # 2026-06-09T21:00:00+02:00 honeypot_ftp src_ip=1.2.3.4
  environment.etc."crowdsec/parsers/s01-parse/honeypot.yaml".text = ''
    filter: "evt.Meta.log_type == 'honeypot'"
    name: custom/honeypot-parser
    description: "Parse honeypot fake service logs"
    grok:
      pattern: "%{TIMESTAMP_ISO8601:time} honeypot_%{WORD:service} src_ip=%{IP:src_ip}"
      apply_on: message
    statics:
      - meta: source_ip
        expression: "evt.Parsed.src_ip"
      - meta: service
        expression: "evt.Parsed.service"
      - target: evt.StrTime
        expression: "evt.Parsed.time"
  '';

  # Scenario: ban any IP that touches a honeypot port — immediate, no threshold
  environment.etc."crowdsec/scenarios/honeypot-scan.yaml".text = ''
    type: trigger
    name: custom/honeypot-scan
    description: "IP touched a honeypot service"
    filter: "evt.Meta.log_type == 'honeypot'"
    groupby: "evt.Meta.source_ip"
    blackhole: 5m
    labels:
      service: honeypot
      type: scan
      remediation: true
  '';

  # ── CrowdSec install collections + endlessh parser ───────────────────────
  systemd.services.crowdsec-install-collections = {
    description = "Install CrowdSec collections and parsers";
    after       = [ "crowdsec.service" ];
    wants       = [ "crowdsec.service" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      Type             = "oneshot";
      RemainAfterExit  = true;
      ExecStart = pkgs.writeShellScript "crowdsec-install-collections" ''
        CONFIG=$(ls /nix/store/*-crowdsec.yaml 2>/dev/null | head -1)
        ${pkgs.crowdsec}/bin/cscli -c "$CONFIG" collections install crowdsecurity/linux 2>/dev/null || true
        ${pkgs.crowdsec}/bin/cscli -c "$CONFIG" collections install crowdsecurity/sshd 2>/dev/null || true
        # endlessh parser — bans IPs that get caught in the tarpit
        ${pkgs.crowdsec}/bin/cscli -c "$CONFIG" parsers install crowdsecurity/endlessh-logs 2>/dev/null || true
        ${pkgs.crowdsec}/bin/cscli -c "$CONFIG" scenarios install crowdsecurity/endlessh-bf 2>/dev/null || true
      '';
    };
  };

  # ── nftables bouncer ──────────────────────────────────────────────────────
  services.crowdsec-firewall-bouncer = {
    after = [ "crowdsec.service" ];
    wants = [ "crowdsec.service" ];
    enable = true;
    registerBouncer.enable = true;
    settings = {
      mode = "nftables";
      nftables = {
        ipv4 = {
          enabled   = true;
          set-only  = false;
          table     = "crowdsec";
          chain     = "crowdsec-chain";
        };
        ipv6 = {
          enabled   = true;
          set-only  = false;
          table     = "crowdsec6";
          chain     = "crowdsec6-chain";
        };
      };
    };
  };
}


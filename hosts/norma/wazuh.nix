# hosts/norma/wazuh.nix
#
# Wazuh manager + OpenSearch + dashboard, brought up first on
# Norma (Oracle Cloud free-tier ARM, ARM Ampere A1, 4 cores / 24GB).
#
# Wazuh is NOT in nixpkgs — Docker-only on NixOS, as noted in the doc's
# Security/Monitoring deferral. This runs the official Wazuh Docker
# images via oci-containers rather than waiting on a native module.
#
# Scope: replaces/supersedes nothing yet. The existing auditd+AIDE+
# security-dashboard setup on the 5 internal hosts keeps running as-is.
# Wazuh agents get added to those hosts as a SEPARATE follow-up step,
# not bundled into this file — see hosts/<host>/wazuh-agent.nix (TODO).

{ config, lib, pkgs, ... }:

let
  wazuhVersion = "4.9.0"; # pin explicitly; check for current stable before applying
in
{
  virtualisation.docker.enable = true;

  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers = {
    wazuh-indexer = {
      image = "wazuh/wazuh-indexer:${wazuhVersion}";
      volumes = [
        "/persist/wazuh/indexer-data:/var/lib/wazuh-indexer"
      ];
      environment = {
        "OPENSEARCH_JAVA_OPTS" = "-Xms2g -Xmx2g"; # conservative on 24GB shared box
      };
      extraOptions = [ "--network=wazuh-net" ];
    };

    wazuh-manager = {
      image = "wazuh/wazuh-manager:${wazuhVersion}";
      volumes = [
        "/persist/wazuh/manager-data:/var/ossec/data"
        "/persist/wazuh/manager-etc:/var/ossec/etc"
      ];
      ports = [
        "1514:1514" # agent event data
        "1515:1515" # agent enrollment
        "55000:55000" # API
      ];
      extraOptions = [ "--network=wazuh-net" ];
      dependsOn = [ "wazuh-indexer" ];
    };

    wazuh-dashboard = {
      image = "wazuh/wazuh-dashboard:${wazuhVersion}";
      volumes = [
        "/persist/wazuh/dashboard-certs:/usr/share/wazuh-dashboard/certs"
      ];
      ports = [
        # bind to WireGuard IP only — see firewall note below
        "10.200.0.8:443:5601"
      ];
      extraOptions = [ "--network=wazuh-net" ];
      dependsOn = [ "wazuh-manager" ];
    };
  };

  systemd.services.docker-network-wazuh-net = {
    description = "Create wazuh-net docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.docker}/bin/docker network inspect wazuh-net >/dev/null 2>&1 || \
        ${pkgs.docker}/bin/docker network create wazuh-net
    '';
  };

  # Dashboard reachable only over the mesh, never on the public IP —
  # mirrors threats.xesh.cc's "WireGuard + home VLANs only" treatment.
  networking.firewall.interfaces."wg-mesh".allowedTCPPorts = [ 443 1514 1515 55000 ];
  networking.firewall.allowedTCPPorts = lib.mkForce [ 22022 ]; # SSH only, public side

  # TODO once manager is confirmed healthy:
  #   - generate enrollment keys per internal host
  #   - add hosts/<host>/wazuh-agent.nix to orion, eridanus, caelum,
  #     andromeda, horologium (the same 5 hosts auditd/AIDE already cover)
  #   - decide whether Wazuh fully replaces the security-dashboard.nix
  #     SSH-pull approach or runs alongside it during a transition period
}


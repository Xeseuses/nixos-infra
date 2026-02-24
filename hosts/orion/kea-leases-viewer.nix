{ config, pkgs, ... }:
{
  networking.firewall.interfaces = {
    vlan10.allowedTCPPorts = [ 9090 ];
    vlan30.allowedTCPPorts = [ 9090 ];
  };

  systemd.services.kea-leases-viewer = {
    description = "Kea DHCP Lease Dashboard";
    after = [ "network.target" "kea-dhcp4-server.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./kea-leases-viewer.py}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}

{ config, pkgs, ... }:
{
  # Kea DHCP Lease Viewer — http://10.40.10.1:9090
  # Readable from VLAN 10 (LAN) and VLAN 30 (Management)

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
      
      User = "nobody";
      Group = "nogroup";
      DynamicUser = false;

      ProtectSystem = false;
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  };
}


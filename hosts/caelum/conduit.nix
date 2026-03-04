{ config, pkgs, ... }:
{
 
  services.matrix-conduit = {
  enable = true;
  settings.global = {
    server_name        = "xesh.cc";
    address            = "0.0.0.0";
    port               = 6167;
    max_request_size   = 20000000;
    allow_registration = false;
    allow_federation   = true;
    trusted_servers    = [ "matrix.org" ];
  };
};  

  networking.firewall.allowedTCPPorts = [
    22 2283 13378 2335 8443 8080 9040 3000 6167
  ];
}

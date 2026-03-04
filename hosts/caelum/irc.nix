{ config, pkgs, ... }:
{
  services.ngircd = {
    enable = true;
    config = ''
      [Global]
        Name = irc.xesh.cc
        Info = Personal IRC
        AdminInfo1 = xeseuses
        Password =

      [Limits]
        MaxConnections = 10
        MaxNickLen = 20

      [Options]
        PAM = no
        SyslogFacility = local1
        LogLevel = 5

      [Operator]
        Name = xeseuses
        Password = 

      [Channel]
        Name = #home
        Topic = OpenClaw home channel
    '';
  };

  networking.firewall.allowedTCPPorts = [
    22 2283 13378 2335 8443 8080 9040 3000 6167 6667
  ];
}

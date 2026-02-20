# hosts/lyra/default.nix
{ config, pkgs, ... }:
{
  imports = [
    # VPS providers usually generate this
    ./hardware-configuration.nix
  ];

  asthrossystems = {
    hostInfo = "VPS - Reverse Proxy Server";
    isServer = true;
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";  # Adjust for your VPS!

  networking = {
    hostName = "lyra";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 51820 ];  # SSH, HTTP, HTTPS, WireGuard
      allowedUDPPorts = [ 51820 ];  # WireGuard
    };
  };

  # === WireGuard VPN Tunnel ===
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];  # VPS side of tunnel
    listenPort = 51820;
    
    privateKeyFile = "/var/lib/wireguard/private.key";
    
    peers = [
      {
        # andromeda (Home Assistant server)
        publicKey = "ANDROMEDA_PUBLIC_KEY_HERE";  # We'll generate this
        allowedIPs = [ "10.100.0.2/32" "10.40.40.0/24" ];  # Allow andromeda + home network
        persistentKeepalive = 25;
      }
    ];
  };

  # === Caddy Reverse Proxy ===
  services.caddy = {
    enable = true;
    
    virtualHosts."ha.xesh.cc" = {
      extraConfig = ''
        reverse_proxy 10.100.0.2:8123 {
          header_up Host {host}
          header_up X-Real-IP {remote}
          header_up X-Forwarded-For {remote}
          header_up X-Forwarded-Proto {scheme}
        }
      '';
    };
    
    # Add more domains as needed
    # virtualHosts."immich.xesh.cc" = {
    #   extraConfig = ''
    #     reverse_proxy 10.100.0.3:2283
    #   '';
    # };
  };

  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "24.11";
}

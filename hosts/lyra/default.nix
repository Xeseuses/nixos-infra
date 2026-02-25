{ config, pkgs, ... }:
{
  imports = [
  ./disk-config.nix
  ./hardware-configuration.nix
  ];

  asthrossystems = {
    hostInfo = "Hetzner CX23 - Reverse Proxy + VPN Server";
    isServer = true;
  };

  sops = {
  defaultSopsFile = ../../secrets/secrets.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";
  secrets."lyra/wireguard/private-key" = {};
};

  boot.loader.grub = {
  enable = true;
  efiSupport = false;
  kernel.sysctl = {
  "net.ipv4.ip_forward" = 1;
  };
}; 
    networking = {
    hostName = "lyra";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
      allowedUDPPorts = [ 51821 ];  # WireGuard
      trustedInterfaces = [ "wg0" ];
    };
  };

  # ── WireGuard Server ──────────────────────────────────────────────────────
  # Hub for andromeda (10.200.0.2) and caelum (10.200.0.3)

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.200.0.1/24" ];
    listenPort = 51821;
   # privateKeyFile = "/var/lib/wireguard/private.key";
    privateKeyFile = config.sops.secrets."lyra/wireguard/private-key".path;
    peers = [
      {
        # andromeda
        publicKey = "Su/GnnDxSCnUpH45jTO3dwZVHk7/VskvwkDscpBISEA=";
        allowedIPs = [ "10.200.0.2/32" "10.40.10.0/24" "10.40.30.0/24" "10.40.40.0/24" "10.40.50.0/24" ];  
      }
      {
        # caelum
        publicKey = "XxG5b+JPvLebcaD49ggCjfcqcElkCa5OAdLWCeQTQz8=";
        allowedIPs = [ "10.200.0.3/32" ];
      }
      {
      # vela
      publicKey = "szfiqi0Uea4O8Wfml0LPQ25jiAbVkSy0jMVusDGNWhU=";
      allowedIPs = [ "10.200.0.4/32" ];
    }
    {
      # phone
      publicKey = "6fYXePTJ2x0bMwlnKiyfVish/Z/h+r4UJhZor/ZBVnQ=";
	      allowedIPs = [ "10.200.0.5/32" ];
	    }
    ];
  };

  # ── Caddy Reverse Proxy ───────────────────────────────────────────────────

  services.caddy = {
    enable = true;
    virtualHosts = {
      "ha.xesh.cc" = {
        extraConfig = "reverse_proxy 10.200.0.2:8123";
      };
      "immich.xesh.cc" = {
        extraConfig = "reverse_proxy 10.200.0.3:2283";
      };
      "audiobooks.xesh.cc" = {
        extraConfig = "reverse_proxy 10.200.0.3:13378";
      };
      "solibieb.nl" = {
        extraConfig = "reverse_proxy 10.200.0.3:8081";
      };
    };
  };

  # ── SSH Bastion ───────────────────────────────────────────────────────────
  # Allows jumping to internal hosts via: ssh -J xeseuses@lyra xeseuses@10.40.x.x
  # Note: internal hosts only reachable if they're in the WireGuard subnet

  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  security.sudo.wheelNeedsPassword = false;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.05";
}


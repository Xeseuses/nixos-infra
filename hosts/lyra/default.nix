# hosts/lyra/default.nix
{ config, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./crowdsec.nix
    ./honeypot.nix
    ./dashboard.nix
  ];

  asthrossystems = {
    hostInfo = "Hetzner CX23 - Reverse Proxy + VPN Server";
    isServer = true;
  };

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile     = "/var/lib/sops-nix/key.txt";
    secrets."lyra/wireguard/private-key" = {};
  };

  boot.loader.grub = {
    enable     = true;
    efiSupport = false;
  };

  networking = {
    hostName = "lyra";
    firewall = {
      enable            = true;
      allowedTCPPorts   = [ 22022 80 443 ];
      allowedUDPPorts   = [ 51821 ];     # WireGuard
      trustedInterfaces = [ "wg0" ];
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  # ── WireGuard Hub ──────────────────────────────────────────────────────────
  # lyra is the hub. All peers connect here.
  #
  # Security principle: lyra only knows WireGuard IPs (10.200.0.x/32).
  # It does NOT route into home VLANs (10.40.x.x) — that's andromeda's job.
  # If lyra is compromised, the attacker cannot reach home network directly.
  #
  # Peer map:
  #   10.200.0.1  lyra       (this host)
  #   10.200.0.2  andromeda  (HA host — proxies ha.xesh.cc)
  #   10.200.0.3  caelum     (services host — immich, audiobooks, solibieb)
  #   10.200.0.4  vela       (laptop road warrior)
  #   10.200.0.5  phone      (Android road warrior)
  #   10.200.0.6  vega       (reserved for future desktop)
  networking.wireguard.interfaces.wg0 = {
    ips        = [ "10.200.0.1/24" ];
    listenPort = 51821;
    privateKeyFile = config.sops.secrets."lyra/wireguard/private-key".path;

    peers = [
      {
        # andromeda — HA VM host
        # Only needs its WireGuard IP — no VLAN routes on lyra
        publicKey  = "Su/GnnDxSCnUpH45jTO3dwZVHk7/VskvwkDscpBISEA=";
        allowedIPs = [ "10.200.0.2/32" ];
      }
      {
        # caelum — services host
        publicKey  = "XxG5b+JPvLebcaD49ggCjfcqcElkCa5OAdLWCeQTQz8=";
        allowedIPs = [ "10.200.0.3/32" ];
      }
      {
	# eridanus — Nextcloud + binary cache
	publicKey  = "pCTHkfjduvIz40MQMSS+mfKNZwQnDnBRSJ1hytTPtxc=";
	allowedIPs = [ "10.200.0.7/32" ];
      }
      {
        # vela — laptop
        publicKey  = "szfiqi0Uea4O8Wfml0LPQ25jiAbVkSy0jMVusDGNWhU=";
        allowedIPs = [ "10.200.0.4/32" ];
      }
      {
        # phone — Android/GrapheneOS road warrior
        publicKey  = "CD6mrCEvQs8c2mCc1Dyfqq6C16rvRTpyqeHwECK7dHI=";
        allowedIPs = [ "10.200.0.5/32" ];
      }
      {
   	# orion — home router, gateway to all home VLANs
	publicKey  = "/Gmm2S5ZFD6J2UQeLo26LUs45GZhD4j87f0V3+TpLAM=";
	allowedIPs = [
	  "10.200.0.6/32"
          "10.40.0.0/16"
         ];
     }
    ];
  };

  # ── Caddy Reverse Proxy ────────────────────────────────────────────────────
  # All services proxy to WireGuard IPs (10.200.0.x), never to 10.40.x.x
  # This keeps lyra isolated from the home network topology.
  services.caddy = {
    enable = true;
    virtualHosts = {
      "ha.xesh.cc" = {
        # andromeda runs nginx on 10.200.0.2:8123 which proxies to HA VM
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
      "cloud.xesh.cc" = {
        extraConfig = "reverse_proxy 10.200.0.7:80";
      };
    };

   };

  
  # ── Users ──────────────────────────────────────────────────────────────────
  users.users.xeseuses = {
    isNormalUser  = true;
    extraGroups   = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  security.sudo.wheelNeedsPassword    = false;
  services.openssh.enable             = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion                 = "25.05";
}


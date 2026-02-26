{ config, pkgs, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./kea-leases-viewer.nix  # DHCP lease dashboard on port 9090
    ./unbound.nix            # Recursive DNS + local hostnames + ad-blocking
  ];

  asthrossystems = {
    hostInfo = "Protectli VP2420 - NixOS Router";
    isRouter = true;
  };

  # ── Boot ──────────────────────────────────────────────────────────────────
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernel.sysctl = {
      "net.ipv4.ip_forward"               = 1;
      "net.ipv4.conf.all.forwarding"      = 1;
      "net.ipv6.conf.all.forwarding"      = 1;
      "net.ipv6.conf.default.forwarding"  = 1;
      "net.ipv6.conf.enp1s0.use_tempaddr" = lib.mkForce 0;
    };
  };

  # ── Avahi (mDNS repeater for HA device discovery across VLANs) ────────────
  services.avahi = {
    enable          = true;
    interfaces      = [ "vlan40" "vlan50" ];
    reflector       = true;
    allowInterfaces = [ "vlan40" "vlan50" ];
  };

  # ── Networking ────────────────────────────────────────────────────────────
  networking = {
    hostName              = "orion";
    networkmanager.enable = false;
    useDHCP               = false;

    interfaces.enp1s0.useDHCP = true;
    interfaces.ens1.useDHCP   = false;

    vlans = {
      vlan10 = { id = 10; interface = "ens1"; };
      vlan20 = { id = 20; interface = "ens1"; };
      vlan30 = { id = 30; interface = "ens1"; };
      vlan40 = { id = 40; interface = "ens1"; };
      vlan50 = { id = 50; interface = "ens1"; };
      vlan60 = { id = 60; interface = "ens1"; };
    };

    interfaces = {
      vlan10 = { useDHCP = false; ipv4.addresses = [{ address = "10.40.10.1"; prefixLength = 24; }]; };
      vlan20 = { useDHCP = false; ipv4.addresses = [{ address = "10.40.20.1"; prefixLength = 24; }]; };
      vlan30 = { useDHCP = false; ipv4.addresses = [{ address = "10.40.30.1"; prefixLength = 24; }]; };
      vlan40 = { useDHCP = false; ipv4.addresses = [{ address = "10.40.40.1"; prefixLength = 24; }]; };
      vlan50 = { useDHCP = false; ipv4.addresses = [{ address = "10.40.50.1"; prefixLength = 24; }]; };
      vlan60 = { useDHCP = false; ipv4.addresses = [{ address = "10.40.60.1"; prefixLength = 24; }]; };
    };

    
    # ── nftables ──────────────────────────────────────────────────────────
    nftables = {
      enable = true;
      tables = {

        # IPv4 forwarding
        orion-forward = {
          family = "ip";
          content = ''
            chain forward {
              type filter hook forward priority 0; policy drop;
              ct state established,related accept
              iifname "vlan30" accept
              iifname "vlan10" accept
              iifname "vlan40" oifname "enp1s0" accept
              iifname "vlan40" oifname "vlan50" accept
              iifname "vlan40" oifname "vlan30" ip saddr 10.40.40.115 ip daddr { 10.40.30.111, 10.40.30.115 } accept
              iifname "vlan50" oifname "enp1s0" accept
              iifname "vlan20" oifname "enp1s0" accept
              iifname "vlan60" oifname "vlan40" accept

            }
          '';
        };

        # IPv4 NAT
        orion-nat = {
          family = "ip";
          content = ''
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              iifname { "vlan10", "vlan20", "vlan30", "vlan40", "vlan50", "vlan60"} oifname "enp1s0" masquerade
            }
          '';
        };

        # IPv6 forwarding
        orion-forward6 = {
          family = "ip6";
          content = ''
            chain forward {
              type filter hook forward priority 0; policy drop;
              ct state established,related accept
              iifname "vlan10" accept
              iifname "vlan30" accept
              iifname "vlan40" oifname "enp1s0" accept
              iifname "vlan40" oifname "vlan50" accept
              iifname "vlan50" oifname "enp1s0" accept
              iifname "vlan20" oifname "enp1s0" accept
              iifname "enp1s0" oifname "vlan10" accept
              iifname "enp1s0" oifname "vlan30" accept
              iifname "enp1s0" oifname "vlan40" accept
              iifname "enp1s0" oifname "vlan50" accept
            }
          '';
        };
   
       };
    };


    # ── Firewall ──────────────────────────────────────────────────────────
    firewall = {
      enable = true;
      interfaces = {
        vlan10 = { allowedTCPPorts = [ 22 53 ];  allowedUDPPorts = [ 53 67 546 547 ]; };
        vlan30 = { allowedTCPPorts = [ 22 53 ];  allowedUDPPorts = [ 53 67 546 547 ]; };
        vlan40 = { allowedTCPPorts = [ 53 ];     allowedUDPPorts = [ 53 67 5353 546 547 ]; };
        vlan50 = { allowedTCPPorts = [ 53 ];     allowedUDPPorts = [ 53 67 5353 546 547 ]; };
        vlan20 = { allowedUDPPorts = [ 67 ]; };

        vlan60 = { allowedTCPPorts = [ 53 ]; allowedUDPPorts = [ 53 67 ]; };

        wg0 = {allowedTCPPorts = [ 22 53 9090 ]; allowedUDPPorts = [ 53 ]; } ;
      };
    };
  };

  networking.firewall.checkReversePath = false;

  networking.firewall.extraInputRules = ''
  iifname "vlan40" ip saddr 10.200.0.0/24 tcp dport 9090 accept
'';

  # ── DHCPv6 Prefix Delegation ──────────────────────────────────────────────
  # Request a prefix from FritzBox and delegate /64s to each VLAN.
  # The hint "::/62" asks for the same prefix back on renewal for stability.
  networking.dhcpcd.extraConfig = ''
    interface enp1s0
    ia_pd 1/::/62 vlan10/0 vlan30/1 vlan40/2 vlan50/3
  '';

  # ── CoreRAD (dynamic Router Advertisements) ───────────────────────────────
  # CoreRAD reads actual interface addresses at runtime so it automatically
  # advertises the correct prefix after every dhcpcd renewal — no hardcoded
  # prefixes, no manual rebuilds needed when the delegated prefix changes.
  services.corerad = {
    enable = true;
    settings = {
      interfaces = [
        {
          name      = "vlan10";
          advertise = true;
          prefix    = [{ prefix = "::/64"; }];
          route     = [{ prefix = "::/0"; }];
        }
        {
          name      = "vlan30";
          advertise = true;
          prefix    = [{ prefix = "::/64"; }];
          route     = [{ prefix = "::/0"; }];
        }
        {
          name      = "vlan40";
          advertise = true;
          prefix    = [{ prefix = "::/64"; }];
          route     = [{ prefix = "::/0"; }];
        }
        {
          name      = "vlan50";
          advertise = true;
          prefix    = [{ prefix = "::/64"; }];
          route     = [{ prefix = "::/0"; }];
        }
        # vlan20 (guest) intentionally omitted — will get Mullvad IPv6 later
      ];
    };
  };

  # ── Kea DHCP (IPv4) ───────────────────────────────────────────────────────
  systemd.services.kea-dhcp4-server = {
    after = [ "network-addresses.target" ];
    wants = [ "network-addresses.target" ];
  };

  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [ "vlan10" "vlan20" "vlan30" "vlan40" "vlan50" "vlan60" ];
      valid-lifetime = 86400;
      subnet4 = [
        {
          id = 10;
          subnet = "10.40.10.0/24";
          pools = [{ pool = "10.40.10.100 - 10.40.10.200"; }];
          option-data = [
            { name = "routers";             data = "10.40.10.1"; }
            { name = "domain-name-servers"; data = "10.40.10.1"; }
          ];
        }
        {
          id = 20;
          subnet = "10.40.20.0/24";
          pools = [{ pool = "10.40.20.100 - 10.40.20.200"; }];
          option-data = [
            { name = "routers";             data = "10.40.20.1"; }
            { name = "domain-name-servers"; data = "1.1.1.1"; }
          ];
        }
        {
          id = 30;
          subnet = "10.40.30.0/24";
          pools = [{ pool = "10.40.30.100 - 10.40.30.200"; }];
          reservations = [
            { hw-address = "f4:e2:c6:20:08:d6"; ip-address = "10.40.30.120"; hostname = "unifi-ap"; }
          ];
          option-data = [
            { name = "routers";                     data = "10.40.30.1"; }
            { name = "domain-name-servers";         data = "10.40.30.1"; }
            { name = "vendor-encapsulated-options"; data = "01:04:0a:28:28:65"; csv-format = false; }
          ];
        }
        {
          id = 40;
          subnet = "10.40.40.0/24";
          pools = [{ pool = "10.40.40.100 - 10.40.40.200"; }];
          reservations = [
            { hw-address = "e8:ff:1e:d2:b0:2f"; ip-address = "10.40.40.104"; hostname = "andromeda"; }
            { hw-address = "7c:83:34:b9:7c:04"; ip-address = "10.40.40.101"; hostname = "caelum"; }
            { hw-address = "7c:83:34:b9:b8:51"; ip-address = "10.40.40.117"; hostname = "eridanus"; }
          ];
          option-data = [
            { name = "routers";             data = "10.40.40.1"; }
            { name = "domain-name-servers"; data = "10.40.40.1"; }
          ];
        }
        {
          id = 50;
          subnet = "10.40.50.0/24";
          pools = [{ pool = "10.40.50.100 - 10.40.50.200"; }];
          option-data = [
            { name = "routers";             data = "10.40.50.1"; }
            { name = "domain-name-servers"; data = "10.40.50.1"; }
          ];
        }	
        {
 	 id = 60;
	 subnet = "10.40.60.0/24";
	 pools = [{ pool = "10.40.60.100 - 10.40.60.200"; }];
         option-data = [
   	   { name = "routers"; data = "10.40.40.101"; }
	   {  name = "domain-name-servers"; data = "10.40.10.1"; }
          ];
        }
      ];
    };
  };

  # ── Users ─────────────────────────────────────────────────────────────────
  users.users.xeseuses = {
    isNormalUser       = true;
    extraGroups        = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  # ── System ────────────────────────────────────────────────────────────────
  security.sudo.wheelNeedsPassword    = false;
  services.openssh.enable             = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion                 = "24.11";
}


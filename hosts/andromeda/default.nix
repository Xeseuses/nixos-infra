# hosts/andromeda/default.nix
{ config, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  asthrossystems = {
    hostInfo = "Beelink EQ12 - Home Assistant OS VM Host";
    isServer = true;
  };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  networking = {
    hostName = "andromeda";
    
    # Disable NetworkManager on bridge interface
    networkmanager.enable = true;
    networkmanager.unmanaged = [ "br0" "enp2s0" ];
    networkmanager.dns = "none";  # ← ADD THIS LINE!

    # Create bridge on enp2s0
    bridges.br0.interfaces = [ "enp2s0" ];
    
    # Configure bridge with current IP
    interfaces.br0 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "10.40.40.104";
        prefixLength = 24;
      }];
    };
    
    defaultGateway = "10.40.40.1";
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    
    firewall = {
      enable = true;
      allowedTCPPorts = [ 8123 ];
      trustedInterfaces = [ "br0" ];
    };
  };

  # Add after networking section
  networking.wireguard.interfaces.wg0 = {
  ips = [ "10.100.0.2/24" ];  # andromeda side of tunnel
  
  privateKeyFile = "/var/lib/wireguard/private.key";
  
  peers = [
    {
      # lyra (VPS)
      publicKey = "jXe+WcEMwBkk57aFNzVasv21GAj5058JqFgIcG0IJxs=";  # We'll generate this
      allowedIPs = [ "10.100.0.0/24" ];  # Route all traffic through VPS (optional)
      endpoint = "172.245.52.108:51820";
      persistentKeepalive = 25;
    }
  ];
};
  # Virtualization
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      runAsRoot = false;
    };
  };

  programs.virt-manager.enable = true;

  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" "libvirtd" "kvm" ];
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "24.11";
}

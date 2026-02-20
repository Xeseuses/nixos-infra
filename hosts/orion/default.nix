# hosts/orion/default.nix - BOOTSTRAP VERSION
{ config, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
 #   ./hardware-configuration.nix
  ];

  # Basic system info
  asthrossystems = {
    hostInfo = "Protectli VP2420 Router";
    isRouter = true;
  };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  # Network - SIMPLE for now
  networking = {
    hostName = "orion";
    useDHCP = false;
    
    # LAN interface gets static IP for management
    interfaces.ens1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "10.40.30.1";  # Router IP on management VLAN
        prefixLength = 24;
      }];
    };
    
    # WAN gets DHCP from FritzBox
    interfaces.enp1s0.useDHCP = true;
  };

  # Enable IP forwarding
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  # Temporary firewall (allow SSH)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # User
  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
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

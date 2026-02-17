{ config, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  # === Custom Options ===
  asthrossystems = {
    hostInfo = "ASUS ROG Flow Z13, i7-12700H, RTX 3050, 16GB RAM";
    isDesktop = true;
    isLaptop = true;
  };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  networking.hostName = "vela";

  # User password - plain for now, SOPS later
  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD..."
    ];
  };

  system.stateVersion = "24.11";
}

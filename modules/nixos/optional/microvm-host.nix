# modules/nixos/optional/microvm-host.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.myinfra.features.microVMs {
  
  # Enable virtualization
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        ovmf = {
          enable = true;
          packages = [(pkgs.OVMF.override {
            secureBoot = true;
            tpmSupport = true;
          }).fd];
        };
      };
    };
  };

  # Enable required kernel modules
  boot.kernelModules = [ "kvm-intel" "kvm-amd" "vfio-pci" ];

  # Increase file descriptor limits for VMs
  systemd.extraConfig = ''
    DefaultLimitNOFILE=1048576
  '';

  # Create bridge for VM networking
  networking.bridges.virbr0.interfaces = [];
  
  networking.interfaces.virbr0 = {
    ipv4.addresses = [{
      address = "192.168.100.1";
      prefixLength = 24;
    }];
  };

  # NAT for VMs
  networking.nat = {
    enable = true;
    internalInterfaces = [ "virbr0" ];
    externalInterface = config.myinfra.networking.primaryInterface;
  };

  # Firewall rules for VMs
  networking.firewall.trustedInterfaces = [ "virbr0" ];

  # Tools for managing VMs
  environment.systemPackages = with pkgs; [
    virt-manager
    qemu
    OVMF
  ];

  # Add user to libvirt group
  users.users.${config.users.users.yourname.name}.extraGroups = [ "libvirtd" ];
}

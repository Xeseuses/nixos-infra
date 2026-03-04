# modules/nixos/optional/microvm-haos.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.asthrossystems.features.homeAssistant.enable {

  # Enable microvm.nix
  microvm.host.enable = true;

  # Home Assistant OS microVM
  microvm.vms.haos = {
    # Use HAOS image
    # We'll download the raw image and convert it
    # For now, we'll use a generic Linux setup
    
    config = {
      microvm = {
        hypervisor = "qemu";
        
        # CPU and memory
        vcpu = 2;
        mem = 2048;  # 2GB RAM
        
        # Bridge network to VLAN 10
        interfaces = [{
          type = "bridge";
          bridge = "br0";  # Assumes br0 is your VLAN 10 bridge
          mac = config.asthrossystems.features.homeAssistant.macAddress;
          id = "haos";
        }];
        
        # Persistent storage for HAOS
        shares = [{
          source = "/var/lib/microvms/haos/shares/haos-data";
          mountPoint = "/data";
          tag = "haos-data";
          proto = "virtiofs";
        }];
        
        # USB passthrough for Sky Connect
        qemu.extraArgs = [
          "-device"
          "usb-host,vendorid=0x${config.asthrossystems.features.homeAssistant.skyConnect.vendorId},productid=0x${config.asthrossystems.features.homeAssistant.skyConnect.productId}"
        ];
      };
      
      # Basic system config for the VM
      system.stateVersion = "24.11";
      
      networking = {
        hostName = "haos";
        useDHCP = false;
        interfaces.haos = {
          ipv4.addresses = [{
            address = config.asthrossystems.features.homeAssistant.ipAddress;
            prefixLength = 24;
          }];
        };
        defaultGateway = "10.40.10.1";
        nameservers = [ "1.1.1.1" "8.8.8.8" ];
      };
      
      # Home Assistant via Docker
      virtualisation.docker.enable = true;
      
      systemd.services.homeassistant = {
        description = "Home Assistant";
        wantedBy = [ "multi-user.target" ];
        after = [ "docker.service" ];
        
        serviceConfig = {
          Type = "simple";
          ExecStart = ''
            ${pkgs.docker}/bin/docker run --rm \
              --name homeassistant \
              --network host \
              -v /data/config:/config \
              -v /etc/localtime:/etc/localtime:ro \
              --device /dev/ttyUSB0 \
              ghcr.io/home-assistant/home-assistant:stable
          '';
          ExecStop = "${pkgs.docker}/bin/docker stop homeassistant";
          Restart = "always";
        };
      };
    };
  };
  
  # Create persistent storage directory
  systemd.tmpfiles.rules = [
    "d /var/lib/microvms/haos/shares/haos-data 0755 root root -"
  ];
  
  # Network bridge for VLAN 10 (if not already configured)
  networking.bridges.br0.interfaces = [ "ens1.10" ];  # Adjust interface!
}

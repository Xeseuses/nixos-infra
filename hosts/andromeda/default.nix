# hosts/andromeda/default.nix
{ config, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  # === Host Info ===
  asthrossystems = {
    hostInfo = "Beelink EQ12, Intel N100, 8GB RAM, 500GB NVMe - Home Assistant Server";
    isServer = true;
  };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  networking = {
    hostName = "andromeda";
    networkmanager.enable = true;
  };

  # === Home Assistant Container ===
  virtualisation = {
    podman = {
      enable = true;
      
      # Enable DNS for containers
      defaultNetwork.settings.dns_enabled = true;
    };
    
    # OCI container for Home Assistant
    oci-containers = {
      backend = "podman";
      
      containers.homeassistant = {
        image = "ghcr.io/home-assistant/home-assistant:stable";
        
        volumes = [
          "/var/lib/hass:/config"
          "/etc/localtime:/etc/localtime:ro"
        ];
        
        environment = {
          TZ = "Europe/Amsterdam";
        };
        
        # Host network mode for device discovery
        extraOptions = [
          "--network=host"
          "--privileged"  # Needed for USB devices
          "--device=/dev/ttyUSB0:/dev/ttyUSB0"  # Zigbee stick (adjust if needed)
        ];
        
        autoStart = true;
      };
    };
  };

  # Create Home Assistant data directory
  systemd.tmpfiles.rules = [
    "d /var/lib/hass 0755 root root -"
  ];

  # Open firewall for Home Assistant
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 
      8123  # Home Assistant web interface
    ];
    
    # mDNS for device discovery
    allowedUDPPorts = [ 5353 ];
  };

  # Users
  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" "dialout" ];  # dialout for USB access
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

{ config, lib, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
  ];

  # === SOPS Configuration ===
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";

    secrets = {
      "users/xeseuses/hashedPassword" = {
        neededForUsers = true;
     };
    };
  };	

  # === Custom Options ===
  asthrossystems = {
    hostInfo = "Beelink EQ12, Intel N100, 16GB RAM, 2TB NVMe";
    
    isServer = true;  # This is a server
    
    features = {
      impermanence = false;
      secureBoot = false;
      encryption = false;
    };
    
    storage = {
      rootDisk = "/dev/nvme0n1";
      filesystem = "ext4";
    };
    
    networking = {
      primaryInterface = "enp1s0";  # Adjust if different
      staticIP = null;  # Use DHCP for now
    };
  };

  # === Boot Configuration ===
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  # === Hardware ===
  hardware.enableRedistributableFirmware = true;

  # === Networking ===
  networking.hostName = "eridanus";  
  networking.networkmanager.enable = true;

  # === SSH ===
  services.openssh = {
    enable = true;
   # settings.PermitRootLogin = "prohibit-password";
  }; 

  # === User ===
  users.users.xeseuses = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
  hashedPasswordFile = config.sops.secrets."users/xeseuses/hashedPassword" .path;


  openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
  ];  
};

  # === Security ===
  security.sudo.wheelNeedsPassword = false;

  # === Essential Packages ===
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
    sops
  ];

}

{ config, pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  # === SOPS ===
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
    hostInfo = "ASUS ROG Flow Z13, i7-12700H, RTX 3050, 16GB RAM";
    isDesktop = true;
    isLaptop = true;
  };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  networking.hostName = "vela";

  # Use SOPS password instead of plain text
  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets."users/xeseuses/hashedPassword".path;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  }; 

  system.stateVersion = "24.11";
}

{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  asthrossystems = {
    hostInfo = "andromeda - Beelink EQ12 - Home Assistant host";
    isServer = true;
    
    features = {
      impermanence = false;
      encryption = false;
      binaryCache.enable = false;
    };
    
    storage = {
      rootDisk = "/dev/nvme0n1";
      filesystem = "ext4";
    };
  };

  networking = {
    hostName = "andromeda";
    interfaces.ens1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "10.30.30.124";
        prefixLength = 24;
      }];
    };
    defaultGateway = "10.30.30.1";
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
  };

  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets."users/xeseuses/hashedPassword".path;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets = {
      "users/xeseuses/hashedPassword".neededForUsers = true;
      "restic_password" = {};
    };
  };

  # ============================================
  # MicroVM Setup - Declarative Hosts Approach
  # ============================================
  
  microvm.host.enable = true;

  # Declare microVM using the declarativeHosts approach
  systemd.services."microvm@haos" = {
    wantedBy = [ "microvms.target" ];
  };

  # Create the microVM state directory
  systemd.tmpfiles.rules = [
    "d /var/lib/microvms 0755 root root -"
    "d /var/lib/microvms/haos 0755 root root -"
    "d /var/lib/microvms/haos/config 0755 root root -"
    "f /var/lib/microvms/haos/flake.nix 0644 root root -"
  ];

  # Write the microVM flake to disk
  environment.etc."microvms/haos/flake.nix".text = ''
    {
      inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
      inputs.microvm.url = "github:astro/microvm.nix";
      
      outputs = { self, nixpkgs, microvm }: {
        nixosConfigurations.haos = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            microvm.nixosModules.microvm
            {
              microvm = {
                hypervisor = "qemu";
                vcpu = 2;
                mem = 2048;
                
                volumes = [{
                  image = "haos.img";
                  mountPoint = "/var";
                  size = 10240;
                }];
                
                shares = [{
                  source = "/var/lib/microvms/haos/config";
                  mountPoint = "/config";
                  tag = "config";
                  proto = "virtiofs";
                }];
                
                interfaces = [{
                  type = "tap";
                  id = "haos-tap";
                  mac = "02:00:00:00:00:01";
                }];
                
                qemu.extraArgs = [
                  "-device" "usb-host,vendorid=0x10c4,productid=0xea60"
                ];
              };
              
              networking = {
                hostName = "haos";
                useDHCP = false;
                interfaces.haos-tap.ipv4.addresses = [{
                  address = "10.30.30.125";
                  prefixLength = 24;
                }];
                defaultGateway = "10.30.30.1";
                nameservers = [ "1.1.1.1" ];
              };
              
              virtualisation.docker.enable = true;
              
              systemd.services.homeassistant = {
                wantedBy = [ "multi-user.target" ];
                after = [ "docker.service" ];
                serviceConfig = {
                  ExecStartPre = "''${pkgs.docker}/bin/docker pull ghcr.io/home-assistant/home-assistant:stable";
                  ExecStart = "''${pkgs.docker}/bin/docker run --rm --name homeassistant --network host --privileged -v /config:/config --device /dev/ttyUSB0 ghcr.io/home-assistant/home-assistant:stable";
                  ExecStop = "''${pkgs.docker}/bin/docker stop homeassistant";
                  Restart = "always";
                };
              };
              
              system.stateVersion = "24.11";
            }
          ];
        };
      };
    }
  '';

  # Copy flake to var
  system.activationScripts.microvm-haos-setup = lib.stringAfter [ "etc" ] ''
    mkdir -p /var/lib/microvms/haos
    cp /etc/microvms/haos/flake.nix /var/lib/microvms/haos/
  '';

  services.restic.backups.haos = {
    repository = "sftp:xeseuses@10.40.40.104:/var/backups/restic/andromeda-haos";
    paths = [ "/var/lib/microvms/haos/config" ];
    passwordFile = config.sops.secrets.restic_password.path;
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 3"
    ];
  };

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "24.11";
}

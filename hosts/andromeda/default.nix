{ config, lib, pkgs, microvm, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  # ============================================
  # Boot
  # ============================================

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # ============================================
  # Custom options
  # ============================================

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

  # ============================================
  # Networking (host)
  # ============================================

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

  # ============================================
  # Users
  # ============================================

  users.users.xeseuses = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets."users/xeseuses/hashedPassword".path;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw=="
    ];
  };

  # ============================================
  # SOPS secrets
  # ============================================

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets = {
      "users/xeseuses/hashedPassword".neededForUsers = true;
      "restic_password" = {};
    };
  };

  # ============================================
  # MicroVM - HAOS guest (declarative)
  # ============================================

  # Ensure persistent directories exist on the host before the VM starts
  systemd.tmpfiles.rules = [
    "d /var/lib/microvms/haos 0755 root root -"
    "d /var/lib/microvms/haos/config 0755 root root -"
  ];

  # Stable /dev/skyconnect symlink regardless of USB enumeration order.
  # Without this the dongle might appear as /dev/ttyUSB0 one boot and
  # /dev/ttyUSB1 the next, breaking Zigbee2MQTT.
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", \
      SYMLINK+="skyconnect", MODE="0660", GROUP="kvm"
  '';

  microvm.host.enable = true;

  microvm.vms.haos = {
    autostart = true;

    # The guest NixOS config is defined inline here.
    # microvm.nix generates the microvm@haos.service with a proper
    # ExecStart from this — no manual systemd wiring needed.
    config = ({ config, pkgs, lib, ... }: {
      imports = [ microvm.nixosModules.microvm ];

      microvm = {
        hypervisor = "qemu";
        vcpu = 2;
        mem = 2048;

        # Pass Sky Connect through by USB vendor/product ID.
        # The host udev rule creates /dev/skyconnect as a stable symlink,
        # but QEMU uses the USB ID directly so it works regardless.
        qemu.extraArgs = [
          "-device" "qemu-xhci"
          "-device" "usb-host,vendorid=0x10c4,productid=0xea60"
        ];

        # TAP interface — host creates haos-tap, guest uses it
        interfaces = [{
          type = "tap";
          id = "haos-tap";
          mac = "02:00:00:00:00:01";
        }];

        # Persistent volume for docker/HA state
        volumes = [{
          image = "/var/lib/microvms/haos/haos.img";
          mountPoint = "/var";
          size = 10240;
        }];

        # Host /var/lib/microvms/haos/config shared into guest at /config.
        # This is the directory restic backs up.
        shares = [{
          source = "/var/lib/microvms/haos/config";
          mountPoint = "/config";
          tag = "config";
          proto = "virtiofs";
        }];
      };

      # Guest networking — static IP on your server VLAN
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

      # Run Home Assistant container inside the guest.
      # Note: /dev/ttyUSB0 is how the Sky Connect appears inside the guest
      # after QEMU USB passthrough. Check guest logs if this path differs.
      systemd.services.homeassistant = {
        wantedBy = [ "multi-user.target" ];
        after = [ "docker.service" ];
        serviceConfig = {
          ExecStartPre = "${pkgs.docker}/bin/docker pull ghcr.io/home-assistant/home-assistant:stable";
          ExecStart = "${pkgs.docker}/bin/docker run --rm --name homeassistant --network host --privileged -v /config:/config --device /dev/ttyUSB0 ghcr.io/home-assistant/home-assistant:stable";
          ExecStop = "${pkgs.docker}/bin/docker stop homeassistant";
          Restart = "always";
        };
      };

      system.stateVersion = "24.11";
    });
  };

  # ============================================
  # Backups — restic to eridanus
  # ============================================

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

  # ============================================
  # Misc
  # ============================================

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "24.11";
}


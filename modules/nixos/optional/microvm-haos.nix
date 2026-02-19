{ config, lib, pkgs, ... }:

# Home Assistant OS microvm module
#
# Runs HAOS as a microvm guest on a NixOS host. This gives us:
# - Full HAOS with Supervisor + add-on store (no compromises)
# - USB passthrough for Sky Connect Zigbee dongle
# - HAOS gets its own IP on the network via a bridge
# - Persistent data volume survives host reboots
# - The NixOS host remains fully declarative in the flake
#
# Why microvm over libvirt?
# microvm.nix is fully declarable in Nix - no virsh commands, no XML,
# no imperative setup. The guest is defined entirely here.
#
# Migration from existing HAOS:
# 1. Deploy andromeda
# 2. Boot HAOS guest (first run = fresh install)
# 3. Restore your HA backup via the onboarding UI
# 4. Verify Sky Connect passthrough works in HA
# 5. Decommission old VM

let
  cfg = config.asthrossystems.homeAssistant;
in
{
  options.asthrossystems.homeAssistant = {
    enable = lib.mkEnableOption "Home Assistant OS microvm";

    skyConnect = {
      vendorId = lib.mkOption {
        type = lib.types.str;
        default = "10c4";
        description = "USB vendor ID of the Sky Connect dongle (from lsusb)";
      };
      productId = lib.mkOption {
        type = lib.types.str;
        default = "ea60";
        description = "USB product ID of the Sky Connect dongle (from lsusb)";
      };
    };

    macAddress = lib.mkOption {
      type = lib.types.str;
      default = "02:00:00:00:00:01";
      description = ''
        MAC address for the HAOS guest network interface.
        Using a deterministic MAC means HAOS gets the same IP from DHCP
        every time. Set a static DHCP reservation for this MAC on your
        router/DHCP server.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/microvms/haos/shares/haos-data";
      description = "Host path for persistent HAOS data (backed up by restic)";
    };

    haosImagePath = lib.mkOption {
      type = lib.types.str;
      description = ''
        Path to the HAOS disk image on the host.
        Download from: https://github.com/home-assistant/operating-system/releases
        Look for: haos_generic-x86-64-<version>.img.xz
        Extract and place at this path before first boot.
        Example:
          wget https://...haos_generic-x86-64-13.2.img.xz
          xz -d haos_generic-x86-64-13.2.img.xz
          mv haos_generic-x86-64-13.2.img /var/lib/microvms/haos/haos.img
      '';
      default = "/var/lib/microvms/haos/haos.img";
    };
  };

  config = lib.mkIf cfg.enable {

    # Ensure data directory exists on the host
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
      "d /var/lib/microvms/haos 0700 root root -"
    ];

    # Bind Sky Connect by USB ID for a stable device path.
    # Without this, the dongle might appear as /dev/ttyUSB0 one boot
    # and /dev/ttyUSB1 the next, breaking Zigbee2MQTT.
    services.udev.extraRules = ''
      # Home Assistant Sky Connect - stable symlink regardless of enumeration order
      SUBSYSTEM=="tty", ATTRS{idVendor}=="${cfg.skyConnect.vendorId}", \
        ATTRS{idProduct}=="${cfg.skyConnect.productId}", \
        SYMLINK+="skyconnect", \
        MODE="0660", GROUP="kvm"
    '';

    # Network bridge so HAOS gets its own IP visible on your LAN/VLAN
    # rather than being NAT'd behind andromeda
    networking.bridges.br-haos.interfaces = [];
    networking.interfaces.br-haos = {
      useDHCP = false; # the bridge itself doesn't need an IP
    };

    # microvm guest definition
    microvm.vms.haos = {
      autostart = true;

      config = {
        microvm = {
          # qemu gives us the best hardware compatibility for HAOS
          # and supports USB passthrough
          hypervisor = "qemu";

          # Pass the Sky Connect through to the guest by USB ID
          # This means even if the host path changes, HAOS always sees it
          qemu.extraArgs = [
            "-device" "qemu-xhci"
            "-device" "usb-host,vendorid=0x${cfg.skyConnect.vendorId},productid=0x${cfg.skyConnect.productId}"
          ];

          # HAOS boot disk - the actual HAOS image
          # HAOS manages its own partitions internally (boot, data, etc.)
          volumes = [
            {
              image = cfg.haosImagePath;
              disk = cfg.haosImagePath;
              # Don't let microvm.nix manage this image - HAOS writes to it directly
              mountPoint = null;
            }
          ];

          # Share host directory into guest for persistent config data.
          # This is what restic backs up.
          # Mount point inside HAOS: handled by HAOS itself at /config
          shares = [
            {
              tag = "haos-data";
              source = cfg.dataDir;
              mountPoint = "/config";
              proto = "virtiofs";
            }
          ];

          # Network: connect guest to the bridge for a real LAN IP
          interfaces = [
            {
              type = "bridge";
              id = "haos-br";
              bridge = "br-haos";
              mac = cfg.macAddress;
            }
          ];

          # HAOS is fairly lightweight but give it enough headroom
          mem = 2048; # 2GB RAM for HAOS + add-ons
          vcpu = 2;
        };

        # No NixOS config needed - this is a HAOS guest, not NixOS
        # microvm.nix requires a minimal system config even for non-NixOS guests
        system.stateVersion = "24.11";
      };
    };

    # Make sure microvm service starts after udev has settled
    # (ensures /dev/skyconnect symlink exists before HAOS boots)
    systemd.services."microvm@haos" = {
      after = [ "systemd-udev-settle.service" ];
      requires = [ "systemd-udev-settle.service" ];
    };
  };
}


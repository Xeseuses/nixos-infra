{ pkgs, modulesPath, lib, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];


  # ── Build size ────────────────────────────────────────────────────────────
  image.fileName = "kepler-keygen.iso";
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";


  # ── INTENTIONALLY OFFLINE ─────────────────────────────────────────────────
  # Policestation exists solely to generate age keys in a clean environment.
  # No network means nothing can exfiltrate keys during generation.
   
  networking = {
    hostName = "kepler";
    useDHCP = lib.mkForce false;
    interfaces = lib.mkForce {};
    wireless.enable = lib.mkForce false;
    networkmanager.enable = lib.mkForce false;
  };

  # No SSH — local access only. You generate keys, write them down / USB, power off.
  services.openssh.enable = false;

  # Auto-login root — you're air-gapped, convenience is fine
  services.getty.autologinUser = lib.mkForce "root";  

  # ── Yubikey readiness (no Yubikey needed yet — services start harmlessly) ──
  # When you get a YubiKey 5 NFC, `age-plugin-yubikey` will let you store the
  # age private key on the device itself so it can never be extracted.
  # The pcscd service below starts silently with no hardware present.
  services.pcscd.enable = true;   # smart card daemon — needed for Yubikey PIV

  # ── Tools ─────────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Core key generation
    age                    # age-keygen — generate the key pair
    age-plugin-yubikey     # future: store private key on Yubikey PIV slot

    # Yubikey management (harmless without hardware)
    yubikey-manager        # ykman — configure the Yubikey
    yubikey-personalization # ykpers — lower-level config

    # Output options — copy key material to USB or print it
    qrencode               # qrencode -t UTF8 — display as QR in terminal
    paperkey               # paperkey — print GPG keys as human-readable backup

    # Minimal usability
    vim
    usbutils               # lsusb — verify Yubikey is detected
  ];

  # ── Helper script ─────────────────────────────────────────────────────────
  # `gen-age-key <hostname>` — one command workflow:
  #   1. Generates a new age keypair
  #   2. Saves private key to /tmp/keys/<hostname>/age-key.txt
  #   3. Prints the public key (add this to .sops.yaml)
  #   4. Optionally displays public key as QR code
  environment.shellAliases = {
    gen-age-key = ''
      bash -c '
        if [ -z "$1" ]; then
          echo "Usage: gen-age-key <hostname>"
          echo "Example: gen-age-key vega"
          exit 1
        fi
        HOSTNAME="$1"
        KEYDIR="/tmp/keys/$HOSTNAME"
        KEYFILE="$KEYDIR/age-key.txt"
        mkdir -p "$KEYDIR"
        chmod 700 "$KEYDIR"

        echo "==> Generating age keypair for $HOSTNAME..."
        age-keygen -o "$KEYFILE"
        chmod 600 "$KEYFILE"

        PUBKEY=$(grep "public key:" "$KEYFILE" | awk "{print \$NF}")

        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  PRIVATE KEY: $KEYFILE"
        echo "║  Copy this file to USB now. It will be lost on shutdown."
        echo "╠══════════════════════════════════════════════════════════════╣"
        echo "║  PUBLIC KEY (add to .sops.yaml):                            ║"
        echo "║  $PUBKEY"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "==> QR code of PUBLIC key (safe to photograph):"
        echo "$PUBKEY" | qrencode -t UTF8
        echo ""
        echo "==> Next steps:"
        echo "    1. Mount a USB: mkdir /mnt/usb && mount /dev/sdX1 /mnt/usb"
        echo "    2. Copy key:    cp $KEYFILE /mnt/usb/"
        echo "    3. Add pubkey to .sops.yaml on your flake"
        echo "    4. Power off:   poweroff"
      ' -- "$@"
    '';

    show-pubkey = ''
      bash -c '
        for f in /tmp/keys/*/age-key.txt; do
          HOST=$(echo "$f" | cut -d/ -f4)
          PUBKEY=$(grep "public key:" "$f" | awk "{print \$NF}")
          echo "$HOST: $PUBKEY"
        done
      '
    '';
  };

  # ── Nix ───────────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.05";
}


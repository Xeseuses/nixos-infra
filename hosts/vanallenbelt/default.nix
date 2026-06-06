{ pkgs, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # ── Identity ──────────────────────────────────────────────────────────────
  networking.hostName = "vanallenbelt";

  # ── Build size ────────────────────────────────────────────────────────────
  # zstd is much faster to build than the default xz, and still small enough
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
  isoImage.isoName = "vanallenbelt-installer.iso";

  # ── Network ───────────────────────────────────────────────────────────────
  # DHCP is fine — new machines always land on VLAN40 (10.40.40.0/24) first
  # or whatever network the hardware is on. Don't fight it.
  networking.useDHCP = true;
  networking.wireless.enable = false;

  # ── SSH ───────────────────────────────────────────────────────────────────
  # The whole point of Drugstore: SSH in immediately after boot, no password.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";       # required — nixos-anywhere runs as root
      PasswordAuthentication = false;
    };
  };

  # Bake your public keys in — add any key you'll ever bootstrap from here.
  # These are PUBLIC keys only; safe to commit.
  users.users.root.openssh.authorizedKeys.keys = [
    # WSL on vega (your current build machine)
    # Replace with: cat ~/.ssh/id_ed25519.pub  (or id_rsa.pub) from WSL
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDiAHl5MuIuTJHR+CciMPIzF1JNNQMwKvi6hzhHfn7tBG+7SmV2+djMh9YosRbaeI6vYoXAq7QPKUUzSbeex4dO2PvCSRHOOrlRMT790Gyg4biG2nMSWDusMkG17zykUTCH29Xi0HD6rk5VzwFJqVyJY/iEIlA02l3BwjHdqemsjwnkSkEjRGLRw1vVVKak9Pii+4GkgCKpI2js4V4C94urbiUqbBABa/lAM0CKWiF2ftLmQbcoSlkEsvF5eRQXKQTbMjcQ7BdSabNveXP+KxqdizRYZEfZSmPI+kUA4nKRFqqLBVg0krKYhOJB2mV+K7ycKEjLxy/gEiS2wRmBq5i9sP5jqjGuk59dRwQr5N9vEvO9hg39Zr0iTvALTUhUqfbViXCJPU4R0PnxSm2yiVhrWfGCrq0fHZ+cBDnu8YKI1vvpFqqUzZaQnSttJ0gyjuJhNKAG8zX4zFfqxYdaN9NmKJCCzfj5NO/FmzSKoOdCMqpTAZlkaYk4zPi6THfewp1rkxOKrOaSS74YCY6VJeN4Cl+/gjFCMpDE3oTujxrQ1sZfjFlkGwbBUb77UZdPEmvWrijPRiTPjpcR7wTzmUNnrKs+oYm5FdbzG7aaI03jEwuefqGOikwiY7WSLTZ1EfDaqp0I5li7I+0CbGNmEU0gNEW5U1G5FItCPnS4fpcrtw== xeseuses@DESKTOP-SRI63L5"

    # vela (laptop) — add if you want to bootstrap from native NixOS too
    # "ssh-ed25519 AAAA_REPLACE_WITH_VELA_KEY xeseuses@vela"
  ];

  # Auto-login root on tty1 for physical access (useful if SSH fails)
  services.getty.autologinUser = "root";

  # ── Tools ─────────────────────────────────────────────────────────────────
  # Everything nixos-anywhere and manual debugging will ever need
  environment.systemPackages = with pkgs; [
    # Install toolchain
    disko                  # declarative disk partitioning
    nixos-anywhere         # remote NixOS installer (also useful on the ISO itself)
    git                    # clone your flake

    # Secret management
    age                    # generate / work with age keys
    sops                   # verify secrets decrypt correctly

    # Disk inspection
    gptfdisk               # gdisk / sgdisk
    parted                 # parted
    lsblk                  # (in util-linux, already present)
    smartmontools          # smartctl — check disk health before installing

    # Network debugging
    curl wget
    iproute2               # ip addr, ip route
    nmap                   # quick port scan if SSH doesn't respond

    # Misc
    jq                     # parse nix eval --json output in scripts
    pv                     # progress bars for dd / pipes
    nix-output-monitor     # nom — nicer nix build output
    vim                    # last resort editor on the ISO
  ];

  # ── Nix ───────────────────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Use your binary cache even from the installer ISO
    substituters = [
      "https://cache.nixos.org"
      # cache.lan won't be reachable unless you're already on VLAN40
      # so we list it as a fallback — failures are silent
    ];
  };

  # ── State version ─────────────────────────────────────────────────────────
  # This is a live ISO, stateVersion doesn't matter much — pick current
  system.stateVersion = "25.05";
}


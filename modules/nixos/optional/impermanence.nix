# modules/nixos/optional/impermanence.nix
{ config, lib, pkgs, inputs, ... }:

lib.mkIf config.asthrossystems.features.impermanence {
  
  # Impermanence setup
  environment.persistence."/persist" = {
    hideMounts = true;
    
    directories = [
      # System
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      
      # NetworkManager
      "/etc/NetworkManager/system-connections"
      
      # Bluetooth
      "/var/lib/bluetooth"
      
      # SOPS keys
      "/var/lib/sops-nix"
      
      # Backups
      "/var/backups"
      
      # Supergfxctl (ASUS GPU switching)
      "/var/lib/supergfxd"
    ];
    
    files = [
      # Machine ID
      "/etc/machine-id"
      
      # SSH host keys
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
    
    # User data
    users.xeseuses = {
      directories = [
        # Important user files
        "Documents"
        "Downloads"
        "Pictures"
        "Videos"
        "Music"
        
        # Development
        "nixos-infra"
        "code"
        
        # Config directories that should persist
        ".ssh"
        ".gnupg"
        
        # Application data
        { directory = ".local/share/niri"; mode = "0700"; }
        ".mozilla"
        ".thunderbird"
        ".config/discord"
        ".config/Code"
        
        # Cache we want to keep (optional)
        ".cache/nix"
      ];
      
      files = [
        # Shell history
        ".bash_history"
        ".zsh_history"
      ];
    };
  };
  
  # Wipe root on boot
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    mkdir /btrfs_tmp
    mount /dev/mapper/cryptroot /btrfs_tmp -o subvol=/
    if [[ -e /btrfs_tmp/@-blank ]]; then
        mkdir -p /btrfs_tmp/old
        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@)" "+%Y%m%d%H%M%S")
        mv /btrfs_tmp/@ "/btrfs_tmp/old/$timestamp"
        btrfs subvolume snapshot /btrfs_tmp/@-blank /btrfs_tmp/@
    fi

    delete_subvolume_recursively() {
        IFS=$'\n'
        for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
            delete_subvolume_recursively "/btrfs_tmp/$i"
        done
        btrfs subvolume delete "$1"
    }

    for i in $(find /btrfs_tmp/old/ -maxdepth 1 -mtime +30); do
        delete_subvolume_recursively "$i"
    done

    umount /btrfs_tmp
  '';
  
  # Create persist directories on first boot
  systemd.tmpfiles.rules = [
    "d /persist/home/xeseuses 0700 xeseuses users"
  ];
}

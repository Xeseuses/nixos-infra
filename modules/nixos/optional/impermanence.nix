# modules/nixos/optional/impermanence.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.asthrossystems.features.impermanence {
  
  environment.persistence."/persist" = {
    hideMounts = true;
    
    directories = [
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      "/var/lib/bluetooth"
      "/var/lib/sops-nix"
    ];
    
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
    
    users.xeseuses = {
      directories = [
        "Documents"
        "Downloads"
        "Pictures"
        "Videos"
        "Music"
        "nixos-infra"
        ".ssh"
        ".gnupg"
        
        # Niri and desktop configs
        { directory = ".config/niri"; mode = "0700"; }
        { directory = ".config/waybar"; mode = "0700"; }
        { directory = ".config/foot"; mode = "0700"; }
        { directory = ".config/fuzzel"; mode = "0700"; }
        { directory = ".config/mako"; mode = "0700"; }
        { directory = ".config/swaylock"; mode = "0700"; }  # ← Add 
        
        # Apps
        ".mozilla"
        ".config/discord"
        ".config/Code"
        
        # Cache
        ".cache/nix"
      ];
      
      files = [
        ".bash_history"
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
  
  systemd.tmpfiles.rules = [
    "d /persist/home/xeseuses 0700 xeseuses users"
  ];
}

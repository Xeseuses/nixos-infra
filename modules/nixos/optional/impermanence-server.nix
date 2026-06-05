{ config, lib, ... }:
lib.mkIf config.asthrossystems.features.impermanenceServer {

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/sops-nix"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  boot.initrd.postDeviceCommands = lib.mkAfter ''
    mkdir /btrfs_tmp
    mount ${config.asthrossystems.features.impermanenceDevice} /btrfs_tmp -o subvol=/
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
}

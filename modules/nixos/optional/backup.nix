# modules/nixos/optional/backup.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.myinfra.features.backup.enable {
  
  # Create backup jobs from the targets defined in options
  services.restic.backups = lib.mapAttrs (name: target: {
    repository = target.repository;
    paths = target.paths;
    passwordFile = config.sops.secrets.restic-password.path;
    
    timerConfig = {
      OnCalendar = target.schedule;
      Persistent = true;
    };
    
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
    
    # Run check monthly
    checkOpts = [ "--with-cache" ];
  }) config.myinfra.features.backup.targets;
  
  # Ensure backup directories exist
  systemd.tmpfiles.rules = 
    lib.mapAttrsToList (name: target: 
      "d ${target.repository} 0700 root root -"
    ) config.myinfra.features.backup.targets;
}

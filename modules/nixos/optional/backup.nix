{ config, lib, pkgs, ... }:

lib.mkIf config.asthrossystems.features.backup.enable {
  
  # Install restic
  environment.systemPackages = [ pkgs.restic ];
  
  # Create backup jobs from options
  services.restic.backups = lib.mapAttrs (name: target: {
    # Repository location
    repository = target.repository;
    
    # Password from SOPS (updated path!)
    passwordFile = config.sops.secrets.restic_password.path;
    
    # What to backup
    paths = target.paths;
    
    # When to run
    timerConfig = {
      OnCalendar = target.schedule;
      Persistent = true;
    };
    
    # Pruning policy (keep old backups)
    pruneOpts = [
      "--keep-daily 7"      # Keep 7 daily backups
      "--keep-weekly 4"     # Keep 4 weekly backups
      "--keep-monthly 6"    # Keep 6 monthly backups
      "--keep-yearly 2"     # Keep 2 yearly backups
    ];
    
    # Run check occasionally
    checkOpts = [
      "--with-cache"
    ];
  }) config.asthrossystems.features.backup.targets;
  
  # SOPS secret for restic password (updated path!)
  sops.secrets.restic_password = {
    mode = "0400";
    owner = "root";
  };
}

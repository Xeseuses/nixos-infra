{ config, lib, pkgs, ... }:

lib.mkIf config.asthrossystems.features.noctalia {
  
  # Noctalia is a shell/panel for niri
  # It's quite new, so we might need to build from source
  
  environment.systemPackages = with pkgs; [
    # Noctalia dependencies
    gtk4
    libadwaita
    
    # We'll add noctalia here when it's in nixpkgs
    # For now, note that you'll configure it manually
  ];
  
  # Persist noctalia config
  environment.persistence."/persist" = lib.mkIf config.asthrossystems.features.impermanence {
    users.xeseuses.directories = [
      ".config/noctalia"
      ".local/share/noctalia"
    ];
  };
  
  # Note: Noctalia might need manual installation initially
  # We can set it up post-install
}

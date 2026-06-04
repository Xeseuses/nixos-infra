{ config, lib, pkgs, ...}:
{
  imports = [
     ./nix.nix
     ./ssh.nix
     ./users.nix
     ./locale.nix
     ./networking.nix
  ];

  environment.systemPackages = with pkgs; [
  
  # Editors
  vim
  nano

  # Version control
  git  

  # System utilities 
  htop
  btop
  wget
  curl
  rsync
  tree
  
  # Network tools
  dig
  nmap

  # File management
  unzip
  zip

  # Process managament
  killall
 
  # Misc
  tmux
  screen
  
  ];
 
  # Enable man pages
  documentation.man.enable = true;
  documentation.dev.enable = true;
  
  hardware.enableRedistributableFirmware = lib.mkDefault true;

}

  

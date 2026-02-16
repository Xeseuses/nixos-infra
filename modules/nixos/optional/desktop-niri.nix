# modules/nixos/optional/desktop-niri.nix
{ config, lib, pkgs, ... }:

lib.mkIf (config.asthrossystems.features.desktop == "niri") {
  
  # Niri compositor
  programs.niri = {
    enable = true;
    package = pkgs.niri;
  };
  
  # Required for Wayland
  programs.xwayland.enable = true;
  
  # Enable Wayland session
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd niri-session";
        user = "greeter";
      };
    };
  };
  
  # Enable sound with Pipewire
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  
  # XDG portal (for screen sharing, file pickers, etc.)
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };
  
  # Fonts
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji
      font-awesome
      (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
    ];
    
    fontconfig = {
      defaultFonts = {
        serif = [ "Noto Serif" ];
        sansSerif = [ "Noto Sans" ];
        monospace = [ "JetBrainsMono Nerd Font" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
  
  # Essential desktop packages
  environment.systemPackages = with pkgs; [
    # Niri ecosystem
    niri
    waybar  # Status bar (or use noctalia's built-in)
    fuzzel  # Application launcher
    mako    # Notification daemon
    swaylock  # Screen locker
    swayidle  # Idle manager
    grim    # Screenshots
    slurp   # Region selector
    wl-clipboard  # Clipboard
    
    # Terminal
    foot    # Fast Wayland terminal
    alacritty  # Alternative terminal
    
    # File manager
    nautilus  # GNOME Files
    
    # Browsers
    firefox-wayland
    
    # Media
    mpv
    imv  # Image viewer
    
    # Utilities
    pavucontrol  # Audio control
    brightnessctl  # Brightness
    playerctl    # Media control
    
    # Communication
    discord
    telegram-desktop
    
    # Development
    vscode
    
    # System
    htop
    btop
    neofetch
  ];
  
  # Persist niri config
  environment.persistence."/persist" = lib.mkIf config.asthrossystems.features.impermanence {
    users.xeseuses.directories = [
      ".config/niri"
      ".config/waybar"
      ".config/foot"
    ];
  };
}

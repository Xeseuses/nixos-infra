# modules/nixos/optional/desktop-niri.nix
{ config, lib, pkgs, ... }:

lib.mkIf (config.asthrossystems.features.desktop == "niri") {

  # Niri compositor
  programs.niri.enable = true;

  # Login manager
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
        user = "greeter";
      };
    };
  };

  # Audio
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # XDG portals
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
    ];
    config.common.default = "*";
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # Fonts
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      font-awesome
      (nerdfonts.override { fonts = [ "JetBrainsMono" "FiraCode" ]; })
    ];
    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" ];
      sansSerif = [ "Noto Sans" ];
      serif     = [ "Noto Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };

  # Desktop packages
  environment.systemPackages = with pkgs; [
    # Niri essentials
    niri
    fuzzel          # App launcher
    waybar          # Status bar
    mako            # Notifications
    swaylock        # Screen locker
    swayidle        # Idle manager
    grim            # Screenshots
    slurp           # Region select
    wl-clipboard    # Clipboard

    # Terminal
    foot
    alacritty

    # File manager
    nautilus

    # Browser
    firefox

    # Media
    mpv
    imv

    # Audio control
    pavucontrol
    playerctl
    brightnessctl

    # Communication
    discord
    telegram-desktop

    # Dev
    vscode

    # Utils
    neofetch
    btop
  ];
}

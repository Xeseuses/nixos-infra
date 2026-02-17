# modules/nixos/optional/desktop-niri.nix
{ config, lib, pkgs, ... }:

lib.mkIf (config.asthrossystems.features.desktop == "niri") {

  programs.niri.enable = true;

  # Login manager (fixed package name)
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
        user = "greeter";
      };
    };
  };

  # Audio
  services.pulseaudio.enable = false;  # Fixed rename
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

  # Fonts (fixed package names)
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji    # ← Fixed rename!
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

  environment.systemPackages = with pkgs; [
    niri
    fuzzel
    waybar
    mako
    swaylock
    swayidle
    grim
    slurp
    wl-clipboard
    foot
    alacritty
    nautilus
    firefox
    mpv
    imv
    pavucontrol
    playerctl
    brightnessctl
    discord
    telegram-desktop
    vscode
    neofetch
    btop
  ];
}

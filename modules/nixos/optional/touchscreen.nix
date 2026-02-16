# modules/nixos/optional/touchscreen.nix
{ config, lib, pkgs, ... }:

lib.mkIf config.asthrossystems.features.touchscreen {
  
  # Enable touchscreen
  services.xserver.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      naturalScrolling = true;
      accelProfile = "adaptive";
    };
  };
  
  # Onboard keyboard (on-screen keyboard for tablet mode)
  environment.systemPackages = with pkgs; [
    onboard
    
    # Gesture support
    libinput-gestures
    
    # Stylus/pen support
    #xournal  # Note-taking
    krita    # Drawing
  ];
  
  # Automatic rotation (for tablet mode)
  hardware.sensor.iio.enable = true;
}

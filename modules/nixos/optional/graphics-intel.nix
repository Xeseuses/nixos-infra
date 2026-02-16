# modules/nixos/optional/graphics-intel.nix
{ config, lib, pkgs, ... }:

lib.mkIf (config.asthrossystems.features.graphics == "intel") {
  
  # Enable OpenGL
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    
    extraPackages = with pkgs; [
      intel-media-driver  # VAAPI
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-compute-runtime  # OpenCL
    ];
  };
  
  # Intel GPU tools
  environment.systemPackages = with pkgs; [
    intel-gpu-tools
    libva-utils
  ];
}

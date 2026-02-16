{ config, lib, pkgs, ... }:

lib.mkIf (config.asthrossystems.features.graphics == "nvidia-hybrid") {
  
  # Enable both Intel and NVIDIA
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    
    # Intel drivers
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-compute-runtime
    ];
  };
  
  # NVIDIA drivers
  services.xserver.videoDrivers = [ "nvidia" ];
  
  hardware.nvidia = {
    # Modesetting required for Wayland
    modesetting.enable = true;
    
    # Power management (important for laptops!)
    powerManagement.enable = true;
    powerManagement.finegrained = true;  # Dynamic power management
    
    # Use open source kernel module (available for RTX 30 series)
    open = true;
    
    # Enable nvidia-settings
    nvidiaSettings = true;
    
    # Package version
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    
    # PRIME configuration for hybrid graphics
    prime = {
      # Enable offload mode (power-saving)
      offload = {
        enable = true;
        enableOffloadCmd = true;  # Adds `nvidia-offload` command
      };
      
      # Bus IDs (we'll need to find these during install)
      # Run: lspci | grep -E "VGA|3D"
      intelBusId = "PCI:0:2:0";    # Usually this for Intel
      nvidiaBusId = "PCI:1:0:0";   # We'll verify during install
    };
  };
  
  # Special udev rules for NVIDIA
  services.udev.extraRules = ''
    # Remove NVIDIA USB xHCI Host Controller devices, if present
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
    
    # Remove NVIDIA USB Type-C UCSI devices, if present
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
    
    # Remove NVIDIA Audio devices, if present
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
  '';
  
  # Environment variables for NVIDIA on Wayland
  environment.sessionVariables = {
    # Force Wayland for Electron apps
    NIXOS_OZONE_WL = "1";
    
    # NVIDIA Wayland hints
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";  # Fixes cursor on some setups
  };
  
  # Offload command for running apps on NVIDIA
  environment.systemPackages = with pkgs; [
    # GPU monitoring
    nvtop
    nvidia-system-monitor-qt
    
    # Create nvidia-offload wrapper
    (pkgs.writeShellScriptBin "nvidia-offload" ''
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only
      exec "$@"
    '')
  ];
  
  # Persist NVIDIA state
  environment.persistence."/persist" = lib.mkIf config.asthrossystems.features.impermanence {
    directories = [
      "/var/lib/nvidia"
    ];
  };
}

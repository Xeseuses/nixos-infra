# modules/nixos/common/locale.nix
{ config, lib, pkgs, ... }:
{
  # Timezone
  time.timeZone = lib.mkDefault "Europe/Amsterdam";  # Adjust to your timezone
  
  # Locale
  i18n = {
    defaultLocale = "en_US.UTF-8";
    
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };
  
  # Console
  console = {
    keyMap = "us";
    # font = "Lat2-Terminus16";  # Uncomment if you want a specific font
  };
}

# modules/nixos/common/networking.nix
{ config, lib, pkgs, ... }:
{
  # Enable NetworkManager
  networking.networkmanager.enable = lib.mkDefault true;
  
  # Firewall defaults
  networking.firewall = {
    enable = lib.mkDefault true;
    
    # Allow ping
    allowPing = true;
    
    # Log refused connections (useful for debugging)
    logRefusedConnections = lib.mkDefault false;  # Disable to avoid log spam
  };
  
  # DNS
  networking.nameservers = lib.mkDefault [
    "1.1.1.1"      # Cloudflare
    "1.0.0.1"      # Cloudflare
    "8.8.8.8"      # Google (backup)
  ];
  
  # Enable IPv6
  networking.enableIPv6 = lib.mkDefault true;
}

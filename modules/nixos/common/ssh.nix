{config, lib, pkgs, ... }:
{
 services.openssh = {
   enable = true;
   
   settings = {
   PermitRootLogin = "prohibit-password";
   PasswordAuthentication = lib.mkDefault true; # Can override per-host
   

   # Performance
   UseDns = false;

   # Key types
   KbdInteractiveAuthentication = false;
  };

  # Host keys to generate
  hostKeys = [
    { 
      path = "/etc/ssh/ssh_host_ed25519_key"
      type = "ed25519";
    }
    
    {
      path = "/etc/ssh/ssh_host_rsa_key";
      type = "rsa";
      bits = 4096;
    }
   ];
  
   # Open firewall automatically
   openFirewall = true;
  };

  programs.ssh = {
    knownHosts = {
   };
 
  # Enable SSH agent
  startAgent = true;
 };
}

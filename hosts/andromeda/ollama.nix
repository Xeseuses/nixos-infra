# Beelink N100 aux-tier model for Hermes Agent: title generation, command
# approval classification, and triage specification. These are short,
# low-reasoning tasks — a 3B model is plenty and keeps RAM footprint small
# alongside the existing Home Assistant VM (capped at 2GB) on this host.
#
# Import this on andromeda alongside its existing homeassistant.nix module.

{ config, lib, pkgs, ... }:

{
  services.ollama = {
    enable = true;
    host = "10.40.40.104"; # andromeda's documented VLAN40 address
    port = 11434;
    acceleration = false; # N100 has no usable GPU for this — CPU inference only

    loadModels = [ "qwen2.5:3b-instruct-q4_K_M" ];

    environmentVariables = {
      # Aux tasks are short-lived and bursty (a title-gen call, then idle).
      # Shorter keep-alive than the RTX box so we don't hold RAM the HA VM
      # might want, while still avoiding a cold load on every single call.
      OLLAMA_KEEP_ALIVE = "10m";
      OLLAMA_CONTEXT_LENGTH = "8192"; # these tasks don't need long context
    };
  };

}


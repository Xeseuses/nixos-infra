# Beelink N100 aux-tier model for Hermes Agent: context compression,
# skills-hub search, and MCP helper operations. These benefit from somewhat
# better summarization/instruction-following than tier A, hence Phi-4-mini
# over Qwen2.5 3B here.
#
# Import this on caelum alongside its existing services-host config
# (Tor gateway, planned SearX, etc.)

{ config, lib, pkgs, ... }:

{
  services.ollama = {
    enable = true;
    host = "10.40.40.101"; # caelum's documented VLAN40 address
    port = 11434;
    package = pkgs.ollama; # CPU-only — N100 has no usable GPU for this

    loadModels = [ "phi4-mini:3.8b-q4_K_M" ];

    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "10m";
      OLLAMA_CONTEXT_LENGTH = "8192";
    };
  };

}


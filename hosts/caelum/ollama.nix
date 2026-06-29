# Beelink N100 (caelum) — Hermes auxiliary tier B: compression, skills_hub,
# mcp. Runs on caelum's own Tor-gateway/services host, separate from
# andromeda's aux tier A, for resilience (one Beelink going down doesn't
# take out both auxiliary task groups).

{ config, lib, pkgs, ... }:

{
  services.ollama = {
    enable = true;
    host = "10.40.40.101"; # caelum's VLAN40 address
    port = 11434;
    package = pkgs.ollama; # CPU-only

    # IMPORTANT: the tag is phi4-mini:3.8b-q4_K_M, NOT phi4-mini:q4_K_M.
    # The short tag does not exist in Ollama's library and pulling it either
    # errors or silently resolves to something else entirely (this bit us
    # once already — caelum ended up running qwen2.5:3b by mistake when a
    # retry of the wrong tag resolved differently than expected).
    loadModels = [ "phi4-mini:3.8b-q4_K_M" ];

    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "10m";
      # Phi-4-mini has a genuine 131K native context (phi3.context_length
      # in its GGUF metadata) — 8192 here is just sized for these
      # particular tasks, not a hardware constraint like horologium's.
      OLLAMA_CONTEXT_LENGTH = "8192";
    };
  };

  # caelum has TWO network interfaces (enp2s0 = VLAN40/general traffic,
  # a separate one for the VLAN60 Tor gateway role) — confirmed via `ip addr`
  # during setup. Port 11434 is scoped to enp2s0 ONLY, deliberately NOT
  # added to the host's global allowedTCPPorts list, since that would open
  # it on the Tor-facing interface too. This is the one host in the
  # constellation where the interface-scoped firewall block is the right
  # choice instead of the global list, given its dual-network role.
  networking.firewall.interfaces."enp2s0".allowedTCPPorts = [ 11434 ];
}


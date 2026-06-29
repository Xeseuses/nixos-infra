# Beelink N100 (andromeda) — runs TWO models for two different purposes:
#
# 1. qwen2.5:3b-instruct-q4_K_M — Hermes auxiliary tier A (title_generation,
#    approval, triage_specifier), called directly by eridanus's hermes-agent
#    config via auxiliary.<task>.base_url.
#
# 2. qwen2.5:1.5b-instruct-q4_K_M — the fast path for delegate_task calls
#    Corvus makes for Home Assistant actions specifically (see SOUL.md and
#    delegation block in hermes-agent.nix). Deliberately smaller than the
#    aux-tier model since HA actions are narrow, single-purpose requests
#    that don't need much reasoning depth — speed matters more here.
#
# Both run on the SAME Ollama instance (one service, two pulled models) —
# Ollama loads/unloads models independently per-request, no need for two
# separate services on one host.

{ config, lib, pkgs, ... }:

{
  services.ollama = {
    enable = true;
    host = "10.40.40.104"; # andromeda's VLAN40 address
    port = 11434;
    package = pkgs.ollama; # CPU-only — N100 has no usable GPU for this

    loadModels = [
      "qwen2.5:3b-instruct-q4_K_M"
      "qwen2.5:1.5b-instruct-q4_K_M"
    ];

    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "10m";
      OLLAMA_CONTEXT_LENGTH = "8192"; # neither model needs long context for these tasks
    };
  };

  # Port 11434 added to andromeda's existing networking.firewall.allowedTCPPorts
  # list in default.nix (was [ 22 ], now [ 22 11434 ]) — no separate
  # interface-scoped firewall block needed, matches the host's existing
  # firewall-management pattern.
}


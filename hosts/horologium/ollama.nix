{ config, lib, pkgs, ... }:

{
  services.ollama = {
    enable = true;

    # Listen on the Servers VLAN (10.40.40.0/24) so eridanus/andromeda/caelum
    # can reach it. Do NOT bind 0.0.0.0 — scope it to the VLAN40 interface
    # address only. Replace with horologium's actual VLAN40 IP if different
    # from the address in your named-clients table (10.40.40.106).
    host = "10.40.40.106";
    port = 11434;

    package = pkgs.ollama-cuda;

    # Preload the model at service start so the first real request isn't
    # paying cold-load latency. Comment out if you'd rather load on demand.
    loadModels = [ "qwen2.5:14b-instruct-q4_K_M" ];

    # How long an idle model stays resident in VRAM before being evicted.
    # 30m keeps it warm through a typical work session without holding
    # VRAM hostage indefinitely if horologium needs it for something else
    # (e.g. local transcoding).
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "30m";
      # Qwen2.5 14B's native context is 32K. Hermes wants 64K minimum.
      # This stretches context via RoPE scaling at some quality cost —
      # test this empirically (see note in chat) before trusting it blindly
      # for long sessions. Drop to 32768 and accept Hermes' warning if
      # quality matters more than hitting the stated minimum.
      OLLAMA_CONTEXT_LENGTH = "65536";
    };
  };

  # Open the firewall on VLAN40 only — your nftables forward policy already
  # restricts VLAN40 traffic per the documented topology, this just opens
  # the local host firewall for the port.
  networking.firewall.interfaces."enp1s0".allowedTCPPorts = [ 11434 ];
  # ^ Replace "enp1s0" with horologium's actual VLAN40-tagged interface name
  #   if different — check with `ip addr` on the host.
}

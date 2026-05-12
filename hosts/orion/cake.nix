{ config, pkgs, lib, ... }:

{
  # Ensure kernel modules are loaded
  boot.kernelModules = [ "sch_cake" "act_mirred" "ifb" ];

  systemd.services.cake-qos = {
    description = "CAKE QoS shaping on WAN interface";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "cake-qos-start" ''
        # Clean up any existing qdiscs
        ${pkgs.iproute2}/bin/tc qdisc del dev enp1s0 root 2>/dev/null || true
        ${pkgs.iproute2}/bin/tc qdisc del dev enp1s0 ingress 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link del ifb0 2>/dev/null || true

        # IFB for ingress
        ${pkgs.iproute2}/bin/ip link add name ifb0 type ifb
        ${pkgs.iproute2}/bin/ip link set ifb0 up

        # Egress (upload): 2.9 Mbit
        ${pkgs.iproute2}/bin/tc qdisc add dev enp1s0 root cake \
          bandwidth 2900kbit ethernet besteffort

        # Ingress (download): 27.3 Mbit
        ${pkgs.iproute2}/bin/tc qdisc add dev enp1s0 handle ffff: ingress
        ${pkgs.iproute2}/bin/tc filter add dev enp1s0 parent ffff: protocol all \
          u32 match u32 0 0 action mirred egress redirect dev ifb0
        ${pkgs.iproute2}/bin/tc qdisc add dev ifb0 root cake \
          bandwidth 27300kbit ethernet ingress besteffort
      '';
      ExecStop = pkgs.writeShellScript "cake-qos-stop" ''
        ${pkgs.iproute2}/bin/tc qdisc del dev enp1s0 root 2>/dev/null || true
        ${pkgs.iproute2}/bin/tc qdisc del dev enp1s0 ingress 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link del ifb0 2>/dev/null || true
      '';
    };
  };
}

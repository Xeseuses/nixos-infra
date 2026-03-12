{ config, lib, pkgs, ... }:
let
  repoPath = "/home/xeseuses/nixos-infra";
  cacheUrl = "http://cache.lan:5000";
  cachePublicKey = "cache.lan:nV+mP0rba5Q3gf/LSxe2AzJgybUYBvFFByWzmcwmG1k=";

  builderScript = pkgs.writeShellScript "nix-nightly-build" ''
    set -euo pipefail

    echo "[nix-builder] Starting nightly build — $(date)"

    # Pull latest config
    cd ${repoPath}
    git pull --ff-only

    # Build all NixOS systems defined in the flake
    SYSTEMS=$(${pkgs.nix}/bin/nix flake show --json 2>/dev/null \
      | ${pkgs.jq}/bin/jq -r '.nixosConfigurations | keys[]')

    for host in $SYSTEMS; do
      echo "[nix-builder] Building nixosConfigurations.${"\${host}"}"
      ${pkgs.nix}/bin/nix build \
        ".#nixosConfigurations.${"\${host}"}.config.system.build.toplevel" \
        --no-link \
        --print-build-logs \
        || echo "[nix-builder] WARNING: build failed for ${"\${host}"}, continuing..."
    done

    # Push all built paths to the binary cache on eridanus
    echo "[nix-builder] Pushing store paths to ${cacheUrl}"
    ${pkgs.nix}/bin/nix copy \
      --to "${cacheUrl}" \
      $(${pkgs.nix}/bin/nix flake show --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.nixosConfigurations | keys[]' \
        | xargs -I{} echo ".#nixosConfigurations.{}.config.system.build.toplevel") \
      || echo "[nix-builder] WARNING: nix copy encountered errors"

    echo "[nix-builder] Done — $(date)"
  '';
in
{
  # Trust the local binary cache
  nix.settings = {
    substituters = [ cacheUrl "https://cache.nixos.org" ];
    trusted-public-keys = [ cachePublicKey "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    # Allow horologium to push to the cache
    trusted-users = [ "xeseuses" "root" ];
  };

  # Nightly build + push timer
  systemd.services.nix-nightly-builder = {
    description = "Nightly NixOS build and binary cache push";
    serviceConfig = {
      Type = "oneshot";
      User = "xeseuses";
      # Give it plenty of time — large builds can take a while
      TimeoutStartSec = "4h";
      # Reduce build priority so it doesn't impact other services
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = "${builderScript}";
    # Needs network and the repo to be accessible
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.timers.nix-nightly-builder = {
    description = "Nightly NixOS build timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Run at 03:00 every night
      OnCalendar = "*-*-* 03:00:00";
      # Run immediately on boot if last run was missed
      Persistent = true;
      # Randomize by up to 30min to avoid thundering herd
      RandomizedDelaySec = "30min";
    };
  };
}


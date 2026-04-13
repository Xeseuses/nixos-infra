{ config, lib, pkgs, ... }:
let
  repoPath = "/home/xeseuses/nixos-infra";
  cacheUrl = "http://cache.lan:5000";
  cachePublicKey = "cache.lan:nV+mP0rba5Q3gf/LSxe2AzJgybUYBvFFByWzmcwmG1k=";
  uploadKeyPath = "/var/lib/nix-serve/upload-private-key.pem";

  git = "${pkgs.git}/bin/git";
  nix = "${pkgs.nix}/bin/nix";
  jq  = "${pkgs.jq}/bin/jq";

  builderScript = pkgs.writeShellScript "nix-nightly-build" ''
    set -euo pipefail

    echo "[nix-builder] Starting nightly build — $(date)"

    # Pull latest config
    cd ${repoPath}
    ${git} pull --ff-only

    # Build all NixOS systems defined in the flake
    SYSTEMS=$(${nix} flake show --json 2>/dev/null \
      | ${jq} -r '.nixosConfigurations | keys[]')

    BUILT_PATHS=""
    for host in $SYSTEMS; do
      echo "[nix-builder] Building nixosConfigurations.$host"
      OUT=$(${nix} build \
        ".#nixosConfigurations.$host.config.system.build.toplevel" \
        --no-link \
        --print-out-paths \
        2>/dev/null) \
        && BUILT_PATHS="$BUILT_PATHS $OUT" \
        || echo "[nix-builder] WARNING: build failed for $host, continuing..."
    done

    if [ -z "$BUILT_PATHS" ]; then
      echo "[nix-builder] ERROR: no paths were built, skipping push"
      exit 1
    fi

    # Push all built toplevel paths in one shot — avoids duplicate upload races
    echo "[nix-builder] Pushing all store paths to ${cacheUrl}"
    ${nix} copy \
      --to "${cacheUrl}?secret-key=${uploadKeyPath}" \
      $BUILT_PATHS \
      && echo "[nix-builder] Push complete" \
      || echo "[nix-builder] WARNING: some paths failed to push"

    echo "[nix-builder] Done — $(date)"
  '';
in
{
  # Trust the local binary cache
  nix.settings = {
    substituters = [ cacheUrl "https://cache.nixos.org" ];
    trusted-public-keys = [ cachePublicKey "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    trusted-users = [ "xeseuses" "root" ];
    secret-key-files = [ uploadKeyPath ];
  };

  # Nightly build + push timer
  systemd.services.nix-nightly-builder = {
    description = "Nightly NixOS build and binary cache push";
    serviceConfig = {
      Type = "oneshot";
      User = "xeseuses";
      TimeoutStartSec = "4h";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = "${builderScript}";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.timers.nix-nightly-builder = {
    description = "Nightly NixOS build timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };
}


{ config, pkgs, ... }:
{
  sops.secrets."caelum/openclaw/anthropic-api-key" = {};

  systemd.services.openclaw = {
    description = "OpenClaw personal AI assistant";
    after    = [ "docker.service" "network-online.target" ];
    wants    = [ "docker.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart        = "on-failure";
      ExecStart      = "${pkgs.writeShellScript "openclaw-start" ''
        export ANTHROPIC_API_KEY=$(cat ${config.sops.secrets."caelum/openclaw/anthropic-api-key".path})
        ${pkgs.docker}/bin/docker rm -f openclaw 2>/dev/null || true
        exec ${pkgs.docker}/bin/docker run --rm \
          --name openclaw \
          -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
          -e OLLAMA_HOST=http://10.40.40.106:11434 \
          -e NODE_PATH="/home/node/.openclaw/node_modules" \
          -v /var/lib/openclaw:/home/node/.openclaw \
          -p 3000:18789 \
          ghcr.io/openclaw/openclaw:latest
      ''}";
      ExecStop       = "${pkgs.docker}/bin/docker stop openclaw";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/openclaw 0750 1000 1000 -"
    "d /var/lib/openclaw-matrix-shadow 0750 1000 1000 -"
  ];
}

# hosts/caelum/firecrawl.nix
#
# Self-hosted Firecrawl (web_extract backend for Hermes coder/researcher),
# deployed via Podman + virtualisation.oci-containers — NOT native Nix
# packages, after this session determined the real upstream architecture
# is genuinely a 5-service Docker Compose application by design, not a
# simple Node server + database that happened to be packaged with Docker.
#
# WHY DOCKER/PODMAN INSTEAD OF NATIVE NIX (read before "simplifying" this):
#   An earlier attempt (this session, via Hermes' `coder` profile) tried
#   packaging Firecrawl as plain NixOS services (buildNpmPackage for the
#   API, a bare PostgreSQL instance, a bare Redis instance). This failed
#   at the very first build step (missing package-lock.json at the pinned
#   revision) and, on investigation, turned out to be solving the wrong
#   problem even if the lockfile issue had been fixed:
#     - The API container's actual entrypoint is `node dist/src/harness.js
#       --start-docker` — a custom process orchestrator (harness.ts) that
#       spawns and supervises the API server, general workers, AND several
#       specialized NuQ (New Unified Queue) worker processes itself. It is
#       not "run the server," it's "run the orchestrator that runs
#       everything else."
#     - PostgreSQL is NOT a generic database — it requires a custom schema
#       (apps/nuq-postgres/nuq.sql, defining nuq.queue_scrape and indexes)
#       applied via a custom init image (ghcr.io/firecrawl/nuq-postgres).
#       A bare `services.postgresql` would never get this schema.
#     - RabbitMQ is a REQUIRED fifth service (NUQ_RABBITMQ_URL) for the
#       NuQ queue's notification mechanism — entirely absent from the
#       first native-Nix attempt, which only knew about Redis + Postgres.
#     - Playwright (browser automation, JS rendering) ships as its own
#       multi-hundred-MB container with a full bundled Chromium — exactly
#       the kind of artifact Nix can package but at a real, disproportionate
#       packaging-effort cost relative to just using the maintainer's own
#       published image.
#   Given all five services are genuinely designed and tested as a unit by
#   upstream, fighting that with hand-rolled native packages was reinventing
#   (and currently mis-modeling) work the Firecrawl team already does
#   correctly. Using their published images via Podman is the pragmatic
#   choice here — consistent with how UniFi already stays on Docker
#   elsewhere in this infrastructure (per the infra doc's own
#   "Infrastructure Improvements" section) for the same kind of reason.
#
# DEPLOYED ON CAELUM, not eridanus — same reasoning as tonight's SearXNG
# deployment: caelum is the documented Services Host, eridanus already
# carries Corvus + coder + researcher + home + Nextcloud + binary cache.
# Reachable from coder/researcher (on eridanus) over the same WireGuard
# tunnel already used for SearXNG (10.200.0.3).
#
# SOURCE: based directly on a verified-working, current third-party
# Docker Compose reference (using upstream's own published ghcr.io images,
# not building from source — sidesteps the stale-tag/lockfile problem
# entirely), cross-checked against upstream's own docker-compose.yaml and
# SELF_HOST.md. NOT yet validated with a real deployment from this
# session — needs a real `nixos-rebuild test` + functional check before
# trusting it, same as everything else built tonight.

{ config, lib, pkgs, ... }:

{
  # ---------------------------------------------------------------------
  # Podman, configured to provide a docker-compatible socket so
  # virtualisation.oci-containers can drive it the same way it would
  # drive real Docker.
  # ---------------------------------------------------------------------
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  virtualisation.oci-containers.backend = "podman";

  # ---------------------------------------------------------------------
  # Secrets
  # ---------------------------------------------------------------------
  sops.secrets."firecrawl-postgres-password" = {
    owner = "root";
  };
  sops.secrets."firecrawl-bull-auth-key" = {
    owner = "root";
  };
  sops.secrets."firecrawl-rabbitmq-password" = {
    owner = "root";
  };
  sops.secrets."firecrawl-nuq-rabbitmq-url" = {
    owner = "root";
  };
  # REQUIRED secrets.yaml content (add these as new top-level keys,
  # matching this session's existing per-secret convention):
  #
  #   firecrawl-postgres-password: |
  #       POSTGRES_PASSWORD=<a real generated password>
  #
  #   firecrawl-bull-auth-key: |
  #       BULL_AUTH_KEY=<a real generated value — protects the Bull Queue
  #       admin UI at /admin/<key>/queues, change from the upstream default
  #       of CHANGEME>
  #
  #   firecrawl-rabbitmq-password: |
  #       RABBITMQ_DEFAULT_PASS=<a real generated password>
  #
  #   firecrawl-nuq-rabbitmq-url: |
  #       NUQ_RABBITMQ_URL=amqp://firecrawl:<THE SAME PASSWORD AS ABOVE>@firecrawl-rabbitmq:5672
  #
  # The last two MUST use the identical password value — this is the
  # duplication explained in the firecrawl-api container's comment below.
  # Generate real passwords with `openssl rand -hex 24` or similar, the
  # same pattern used for searxng-secret-key earlier this session.

  # ---------------------------------------------------------------------
  # Custom Podman network — REQUIRED, easy to miss. Unlike Docker Compose,
  # virtualisation.oci-containers does NOT auto-create a network just
  # because containers reference it via `--network=firecrawl` in
  # extraOptions. Without this oneshot, every container below would fail
  # to start with a "network not found" error. Confirmed via a working
  # community pattern for exactly this situation (NixOS Discourse:
  # "Docker/Podman network create - Nix?").
  # ---------------------------------------------------------------------
  systemd.services."podman-network-firecrawl" = {
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    wantedBy = [ "multi-user.target" ];
    script = ''
      ${pkgs.podman}/bin/podman network inspect firecrawl > /dev/null 2>&1 || \
        ${pkgs.podman}/bin/podman network create firecrawl
    '';
  };

  # Every Firecrawl container needs this network created first. Listed
  # individually per-container (via the `dependsOn`-equivalent systemd
  # override below) rather than relying on oci-containers' own
  # `dependsOn` key alone, since that key only orders containers RELATIVE
  # TO EACH OTHER, not relative to this separate network-creation unit.
  systemd.services."podman-firecrawl-redis".after = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-redis".requires = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-rabbitmq".after = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-rabbitmq".requires = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-nuq-postgres".after = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-nuq-postgres".requires = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-playwright".after = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-playwright".requires = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-api".after = [ "podman-network-firecrawl.service" ];
  systemd.services."podman-firecrawl-api".requires = [ "podman-network-firecrawl.service" ];
  # CONFIRMED (not just inferred) against nixpkgs' own oci-containers.nix
  # source: each container's systemd unit is named
  # "${backend}-${containerName}.service" — i.e. exactly
  # "podman-firecrawl-<name>.service" given backend = "podman" and our
  # container attribute names above. The dependsOn option itself is also
  # confirmed real, adding to both After= and Requires= automatically —
  # used correctly on firecrawl-api below without needing the manual
  # per-container wiring this network-creation block needed (dependsOn
  # only orders containers relative to EACH OTHER, not relative to this
  # separate network-creation unit, which is why the explicit lines above
  # are still necessary).

  # ---------------------------------------------------------------------
  # Persistent data — survives container recreation, not just restarts.
  # ---------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d /var/lib/firecrawl 0750 root root - -"
    "d /var/lib/firecrawl/postgres-data 0750 root root - -"
    "d /var/lib/firecrawl/rabbitmq-data 0750 root root - -"
    "d /var/lib/firecrawl/redis-data 0750 root root - -"
  ];

  virtualisation.oci-containers.containers = {

    # ── Redis — job queue + caching ──────────────────────────────────────
    firecrawl-redis = {
      image = "redis:alpine";
      autoStart = true;
      extraOptions = [ "--network=firecrawl" ];
      volumes = [ "/var/lib/firecrawl/redis-data:/data" ];
      cmd = [ "redis-server" "--bind" "0.0.0.0" ];
    };

    # ── RabbitMQ — NuQ notification transport ────────────────────────────
    firecrawl-rabbitmq = {
      image = "rabbitmq:3-management";
      autoStart = true;
      extraOptions = [ "--network=firecrawl" ];
      volumes = [ "/var/lib/firecrawl/rabbitmq-data:/var/lib/rabbitmq" ];
      environmentFiles = [
        config.sops.secrets."firecrawl-rabbitmq-password".path
      ];
      environment = {
        RABBITMQ_DEFAULT_USER = "firecrawl";
      };
      # NOTE: RABBITMQ_DEFAULT_PASS is expected to live INSIDE the
      # environmentFile referenced above (as a real KEY=VALUE line,
      # RABBITMQ_DEFAULT_PASS=<value>), not duplicated here as a plaintext
      # default — confirm this secret's content is formatted that way
      # before first deploy.
    };

    # ── nuq-postgres — custom schema, NOT a generic Postgres ─────────────
    firecrawl-nuq-postgres = {
      image = "ghcr.io/firecrawl/nuq-postgres:latest";
      autoStart = true;
      extraOptions = [ "--network=firecrawl" ];
      volumes = [ "/var/lib/firecrawl/postgres-data:/var/lib/postgresql/data" ];
      environmentFiles = [
        config.sops.secrets."firecrawl-postgres-password".path
      ];
      environment = {
        POSTGRES_USER = "firecrawl";
        POSTGRES_DB = "firecrawl";
      };
      # NOTE: POSTGRES_PASSWORD is expected inside the environmentFile
      # above, same convention as RabbitMQ's password.
      cmd = [ "postgres" "-c" "cron.database_name=firecrawl" ];
      # CRITICAL, easy to miss: per the reference deployment this is based
      # on, omitting the cron.database_name flag causes the image's init
      # script to exit with code 3, killing the container before the API's
      # health check can ever pass. Do not remove this even though it
      # looks redundant with POSTGRES_DB above.
    };

    # ── Playwright service — browser automation / JS rendering ──────────
    firecrawl-playwright = {
      image = "ghcr.io/firecrawl/playwright-service:latest";
      autoStart = true;
      extraOptions = [ "--network=firecrawl" ];
      environment = {
        PORT = "3000";
        BLOCK_MEDIA = "false";
        MAX_CONCURRENT_PAGES = "10";
      };
    };

    # ── API + harness (spawns workers internally) ────────────────────────
    firecrawl-api = {
      image = "ghcr.io/firecrawl/firecrawl:latest";
      autoStart = true;
      extraOptions = [ "--network=firecrawl" ];
      # Bind only to caelum's WireGuard interface — same trust boundary as
      # SearXNG (10.200.0.3), so coder/researcher on eridanus reach this
      # over the existing tunnel, with no need to open anything on
      # caelum's LAN-facing interface or expose it publicly via lyra.
      ports = [ "10.200.0.3:3002:3002" ];
      dependsOn = [
        "firecrawl-redis"
        "firecrawl-rabbitmq"
        "firecrawl-nuq-postgres"
        "firecrawl-playwright"
      ];
      environmentFiles = [
        config.sops.secrets."firecrawl-postgres-password".path
        config.sops.secrets."firecrawl-bull-auth-key".path
        config.sops.secrets."firecrawl-nuq-rabbitmq-url".path
      ];
      environment = {
        HOST = "0.0.0.0";
        PORT = "3002";
        REDIS_URL = "redis://firecrawl-redis:6379";
        REDIS_RATE_LIMIT_URL = "redis://firecrawl-redis:6379";
        PLAYWRIGHT_MICROSERVICE_URL = "http://firecrawl-playwright:3000/scrape";
        POSTGRES_HOST = "firecrawl-nuq-postgres";
        POSTGRES_PORT = "5432";
        POSTGRES_USER = "firecrawl";
        POSTGRES_DB = "firecrawl";
        USE_DB_AUTHENTICATION = "false";
        ENV = "local";
      };
      # CORRECTNESS FIX: NUQ_RABBITMQ_URL is NOT set as a plain `environment`
      # value here, because it needs the RabbitMQ password embedded directly
      # in the amqp:// URL (amqp://firecrawl:<password>@firecrawl-rabbitmq:5672)
      # — trying to assemble that from two separately-sourced secrets inside
      # plain Nix attrset values isn't clean. Instead, the FULL line
      # (NUQ_RABBITMQ_URL=amqp://firecrawl:<password>@firecrawl-rabbitmq:5672)
      # lives directly inside the firecrawl-nuq-rabbitmq-url secret itself —
      # see the sops.secrets block above. This means the RabbitMQ password
      # is duplicated across two secrets (this one and
      # firecrawl-rabbitmq-password, used for RABBITMQ_DEFAULT_PASS on the
      # rabbitmq container itself) — both MUST contain the same password
      # value, or the api container will fail to authenticate to RabbitMQ.
      # Not elegant, but correct and simple — flagged rather than left as
      # the previous draft's broken blank-password placeholder.
    };
  };

  # Firewall: same pattern as SearXNG — only the WireGuard interface,
  # nothing on the LAN-facing interface, nothing public.
  networking.firewall.interfaces.wg0.allowedTCPPorts = [ 3002 ];
}


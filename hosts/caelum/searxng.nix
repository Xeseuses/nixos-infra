# hosts/caelum/searxng.nix
#
# Self-hosted SearXNG metasearch instance, deployed to give `coder` and
# `researcher` (Hermes profiles on eridanus) a free, private, rate-limit-free
# web_search backend — replacing the "no messaging platforms enabled" /
# "no web search tool" gap discovered when testing those profiles live.
#
# ARCHITECTURE:
#   - NixOS has no separate `services.searxng` module; the documented,
#     confirmed-working pattern (NixOS Wiki, checked this session) is to use
#     the existing `services.searx` module with `package = pkgs.searxng`
#     swapped in — searx and searxng share the same module, only the
#     package differs.
#   - Bound to caelum's WireGuard IP (10.200.0.3) only — NOT 0.0.0.0, NOT the
#     home VLAN. The only consumer right now is lyra (the reverse proxy),
#     which already reaches caelum over this exact tunnel for two other
#     services (Immich :2283, Audiobookshelf :13378) per the infra doc's
#     "Public Services (via lyra)" table. This keeps the same trust
#     boundary those services already use, not a new one.
#   - JSON output format is REQUIRED for Hermes to consume results at all —
#     SearXNG ships with JSON disabled by default; the documented failure
#     mode without this is HTTP 403, not a connection error, which is easy
#     to misdiagnose as "the service isn't reachable" when it actually is.
#
# CONFIRMED via Hermes' own docs (this session): SearXNG is SEARCH-ONLY.
# It does not perform page-content extraction (web_extract). researcher's
# `browser`/extraction capability still needs a separate provider
# (Firecrawl/Tavily/Exa) — deliberately deferred, not yet decided. Do not
# assume this module alone gives researcher full "search AND read pages"
# capability; it only gives it search.

{ config, lib, pkgs, ... }:

{
  # CORRECTNESS FIX (caught via real upstream issue, not assumed): the
  # original draft used `services.searx.environmentFile` to deliver
  # SEARXNG_SECRET, following the NixOS Wiki's example verbatim. That
  # pattern is CONFIRMED BROKEN for this exact module under its default
  # execution mode — nixpkgs issue #292652 reports that when SearXNG runs
  # under uWSGI (the module's default), environmentFile's variables reach
  # only the one-shot `searx-init` service, NOT the actual long-running
  # uWSGI vassal process — so SEARXNG_SECRET silently never makes it to
  # the running instance. The failure is not a crash: SearXNG starts
  # anyway and just logs an ERROR-level line ("server.secret_key is not
  # changed. Please use something else instead of ultrasecretkey") while
  # continuing to run on the placeholder key — exactly the kind of
  # silent-but-logged failure this session has hit more than once
  # elsewhere (Hermes' multiplex_profiles, sops-nix's setupSecrets).
  #
  # FIX: use a sops-nix TEMPLATE instead, which renders the secret value
  # directly into a generated settings.yml at activation time (via
  # sops.templates, not environmentFile) and points
  # `services.searx.settingsFile` at that rendered output. This goes
  # through the module's actual settings.yml parsing path, which is
  # confirmed to read secret_key correctly (it's the same path
  # `services.searx.settings.server.secret_key` uses) — sidestepping the
  # broken environmentFile/uWSGI interaction entirely. The secret's
  # plaintext is never embedded in a Nix-store-readable derivation (sops
  # templates render to /run/secrets-rendered, not the store) and never
  # appears in this repo's plaintext source — only the encrypted form
  # does, same guarantee the environmentFile approach was trying for, via
  # a path that's actually confirmed to work for this module.

  sops.secrets."searxng-secret-key" = {
    # No owner/group override needed — this is consumed only by the
    # sops.templates render below, never read directly by the searx
    # service itself.
  };

  sops.templates."searxng-settings.yml" = {
    content = ''
      use_default_settings: true

      general:
        debug: false
        instance_name: "caelum-searxng"
        donation_url: false
        contact_url: false
        privacypolicy_url: false
        enable_metrics: false

      server:
        bind_address: "10.200.0.3"
        port: 8080
        secret_key: "${config.sops.placeholder."searxng-secret-key"}"

      search:
        formats:
          - html
          - json
    '';
    # CORRECTNESS FIX (caught via real activation error, not assumed): the
    # first draft of this template had no owner/group, so the rendered
    # file at /run/secrets/rendered/searxng-settings.yml defaulted to
    # root-only permissions. The searx.service unit runs as the dedicated
    # `searx` system user (the module's standard default), which could
    # not read it — confirmed via PermissionError: [Errno 13] in
    # searx.service's own startup traceback. Setting owner/group here so
    # the actual runtime user of the service can read its own settings.
    owner = "searx";
    group = "searx";
  };
  # VERIFIED (not just plausible): config.sops.placeholder.<name> and
  # sops.templates.<name>.content are confirmed real, current sops-nix
  # features per the official README (Mic92/sops-nix) — the exact pattern
  # used here (secret_key-style value interpolated into a YAML template,
  # rendered to /run/secrets-rendered/<name> at activation) matches the
  # README's own documented example precisely. Confirm only that your
  # flake's sops-nix input is recent enough to include sops.templates —
  # it's a few years old as a feature, so this should be safe on any
  # reasonably current pin, but hasn't been checked against this repo's
  # actual flake.lock from here.

  services.searx = {
    enable = true;
    package = pkgs.searxng;
    redisCreateLocally = true;

    # Point at the sops-rendered file instead of letting the module
    # generate its own settingsFile from `services.searx.settings.*` —
    # this is the one config value secret_key needs to land in, and the
    # template above already contains every other setting we need, so
    # there's no separate `settings = { ... }` block below duplicating it.
    settingsFile = config.sops.templates."searxng-settings.yml".path;
  };

  # Firewall: only allow the WireGuard interface to reach this port.
  # caelum's existing wg0 interface is CONFIRMED (via `ip a` on caelum,
  # this session) to be 10.200.0.3/24, matching the infra doc's WireGuard
  # topology table exactly — lyra already reaches caelum over this same
  # tunnel for two other services (Immich :2283, Audiobookshelf :13378).
  networking.firewall.interfaces.wg0.allowedTCPPorts = [ 8080 ];
}


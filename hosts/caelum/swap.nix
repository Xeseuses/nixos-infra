# hosts/caelum/swap.nix
#
# 4GB swapfile on caelum. Added this session after a real freeze during
# nixos-rebuild: caelum has only 8GB RAM (smallest in the fleet), zero
# swap configured previously, and was running Immich (4 containers) +
# UniFi (2 containers) before this session added 5 more for Firecrawl —
# 11 containers total on the smallest-RAM host. The freeze coincided with
# simultaneous image pulls + Postgres/RabbitMQ first-boot init, a genuine
# resource burst with no cushion (free -h showed 2.4Gi free, 0B swap at
# the time).
#
# This is meant as burst insurance, not a fix for genuine sustained
# undersizing — if caelum needs swap constantly under normal steady-state
# load (check with `free -h` / `vmstat` after things have been running
# calmly for a while), that's a sign it may need more done about it than
# a swapfile, not less.
#
# CONFIRMED correct for btrfs (caelum's root filesystem, confirmed via
# `lsblk -f` this session — /partition-root is btrfs): current nixpkgs'
# swapDevices implementation already runs `btrfs filesystem mkswapfile`
# (not plain mkswap) for btrfs targets, which correctly handles
# NoCoW/checksumming requirements internally. An older, frequently-cited
# Discourse thread / nixpkgs issue (#156829, from 2022) describing
# swapDevices failing on btrfs predates this fix — verified directly
# against current nixpkgs source (nixos/modules/config/swap.nix) before
# writing this, not assumed from the old thread.

{ ... }:

{
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096; # MiB — 4GB, deliberately conservative (see header note)
    }
  ];
}


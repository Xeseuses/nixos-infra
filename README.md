# NixOS Infrastructure

A fully declarative NixOS homelab, managed as code. The repository covers network, services, security, and host configuration across a small fleet of systems.

## Design Principles

- Declarative: all configuration is defined in Nix.
- Reproducible: identical configuration produces identical systems.
- Version controlled: changes are tracked in git, with secrets stored encrypted.
- Modular: shared modules are reused across hosts through custom options.
- Self-hosted: core infrastructure services run on-site.
- Hardened: firewalling, intrusion detection, integrity monitoring, and audit logging are enabled where appropriate.

## Fleet

| Hostname | Hardware | Role | Status |
| --- | --- | --- | --- |
| orion | Protectli VP2420 | Router, VLANs, DHCP, DNS, firewall | Live |
| eridanus | Beelink EQ12 (N100, 16 GB) | Nextcloud, binary cache, security dashboard | Live |
| caelum | Beelink EQ12 | Immich, Audiobookshelf, UniFi, SearXNG | Live |
| andromeda | Beelink EQ12 | Home Assistant VM host | Live |
| horologium | Custom system (i5-13500, 16 GB, ZFS) | Media server and automation stack | Live |
| lyra | VPS | Reverse proxy, VPN hub, honeypot | Live |
| vela | ASUS ROG Flow Z13 | Encrypted laptop, desktop environment | Live |
| vega | Minisforum SER8 | Desktop | Planned |

## Network

The home network is segmented into multiple VLANs for clients, guests, management, servers, IoT, and Tor traffic. DNS is split across recursive, filtering, and authoritative layers, with internal routing handled through the router host.

WireGuard is used for remote access and service exposure. The VPS acts as the public entry point, while internal VLAN routing remains anchored on the home router for resilience.

## Security

Security controls include firewalling, honeypot services, collaborative intrusion prevention, automatic banning, audit logging, and file integrity monitoring.

Host-level hardening is enabled on selected systems, with encrypted storage and key-based SSH access on mobile and remote devices. Secrets are encrypted with SOPS and age before being committed to the repository.

## Services

- Nextcloud for file sync, calendar, contacts, notes, and tasks.
- Immich for photo and video management.
- Home Assistant for home automation.
- Audiobookshelf for audiobook hosting.
- Jellyfin and related media tooling for streaming.
- UniFi Network Application for access point management.
- SearXNG for self-hosted, privacy-respecting web search.

## Repository Structure

```text
nixos-infra/
├── flake.nix
├── flake.lock
├── .sops.yaml
├── secrets/
├── modules/
│   ├── options.nix
│   └── nixos/
│       ├── common/
│       └── optional/
├── hosts/
│   ├── orion/
│   ├── lyra/
│   ├── eridanus/
│   ├── caelum/
│   ├── andromeda/
│   ├── horologium/
│   └── vela/
└── pkgs/
```

## Usage

### Deploy a host

```bash
sudo nixos-rebuild switch --flake .#hostname
```

### Provision a new machine

```bash
nix run .#xesh-bootstrap -- \
  --hostname <newhost> \
  --target <ip> \
  --age-key /path/to/age-key.txt
```

### Manage secrets

```bash
sops secrets/secrets.yaml
sops updatekeys secrets/secrets.yaml
```

### Build installer images

```bash
nix build .#nixosConfigurations.<name>.config.system.build.isoImage --print-out-paths
```

## References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Disko](https://github.com/nix-community/disko)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [CrowdSec](https://www.crowdsec.net/)
- [AIDE](https://aide.github.io/)


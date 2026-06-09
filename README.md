# nixos-infra

Fully declarative NixOS homelab. Constellation-themed hostnames, everything in Nix, no manual configuration.

Custom options exposed under `asthrossystems.*` for reuse across machines.

---

## Fleet

| Hostname | Hardware | Role | Status |
|----------|----------|------|--------|
| **orion** | Protectli VP2420 | Router — VLANs, nftables, Kea DHCP, AdGuard, NSD | live |
| **eridanus** | Beelink EQ12 (N100, 16GB) | Binary cache (harmonia), backups | live |
| **caelum** | Beelink EQ12 | Immich, Audiobookshelf, Solibieb | live |
| **andromeda** | Beelink EQ12 | Home Assistant VM host (libvirt) | live |
| **horologium** | Custom (i5-13500, 16GB, ZFS) | Media server — Jellyfin, Arr stack | live |
| **lyra** | Hetzner CX23 VPS | Caddy reverse proxy, WireGuard hub, honeypot | live |
| **vela** | ASUS ROG Flow Z13 | Encrypted laptop — Niri desktop | live |
| **vega** | Minisforum SER8 | Desktop (dual-boot) | planned |

---

## Network

```
Internet
   │
FritzBox (192.168.178.0/24)
   │
orion — NixOS Router (Protectli VP2420)
   │    AdGuardHome → Unbound → NSD
   │    Kea DHCP · CoreRAD · nftables
   │
Mikrotik Switch
   ├── VLAN10  10.40.10.0/24   LAN
   ├── VLAN20  10.40.20.0/24   Guest
   ├── VLAN30  10.40.30.0/24   Management
   ├── VLAN40  10.40.40.0/24   Servers
   ├── VLAN50  10.40.50.0/24   IoT
   └── VLAN60  10.40.60.0/24   Tor
```

**WireGuard** — hub on lyra (`10.200.0.1`):

```
lyra (hub)
├── orion      10.200.0.6  — gateway to all home VLANs
├── andromeda  10.200.0.2  — HA proxy
├── caelum     10.200.0.3  — services
├── vela       10.200.0.4  — laptop road warrior
└── phone      10.200.0.5  — GrapheneOS road warrior
```

**DNS stack** (orion):

```
clients → AdGuardHome :53 (blocklists, per-client rules, query log)
               ↓
          Unbound :5335 (DNSSEC, DoT to Quad9)
               ↓
           NSD :5354 (authoritative: lan. + xesh.cc split-horizon)
```

**Public services** — exposed via lyra over WireGuard, no ports open at home:

| Domain | Service | Host |
|--------|---------|------|
| `ha.xesh.cc` | Home Assistant | andromeda |
| `immich.xesh.cc` | Immich | caelum |
| `audiobooks.xesh.cc` | Audiobookshelf | caelum |
| `solibieb.nl` | Django web app | caelum |
| `threats.xesh.cc` | Honeypot dashboard (WireGuard only) | lyra |

**Honeypot** (lyra):

- Port 22 → endlessh-go SSH tarpit
- Port 22022 → real SSH
- Ports 21, 23, 3306 → fake FTP / telnet / MySQL
- CrowdSec with nftables bouncer

---

## Repository Structure

```
nixos-infra/
├── flake.nix                     # All hosts + packages + apps
├── flake.lock
├── .sops.yaml                    # Age key configuration
├── secrets/
│   └── secrets.yaml              # Encrypted with SOPS
├── modules/
│   ├── options.nix               # asthrossystems.* custom options
│   └── nixos/
│       ├── common/               # Loaded on every host
│       │   ├── nix.nix           # Binary cache, GC, flakes
│       │   ├── ssh.nix
│       │   ├── users.nix
│       │   ├── locale.nix
│       │   └── networking.nix
│       └── optional/             # Feature modules
│           ├── backup.nix
│           ├── binary-cache.nix
│           ├── impermanence.nix
│           └── impermanence-server.nix
├── hosts/
│   ├── orion/
│   │   ├── adguardhome.nix
│   │   ├── nsd.nix
│   │   ├── unbound.nix
│   │   └── wireguard.nix
│   ├── lyra/
│   │   ├── honeypot.nix
│   │   ├── crowdsec.nix
│   │   └── dashboard.nix
│   ├── eridanus/
│   ├── caelum/
│   ├── andromeda/
│   ├── horologium/
│   └── vela/
└── pkgs/
    ├── xesh-bootstrap/           # nixos-anywhere wrapper
    └── xesh-postinstall/         # First-boot helper
```

---

## Usage

**Deploy:**

```bash
# Locally
sudo nixos-rebuild switch --flake .#hostname

# Remotely
nixos-rebuild switch --flake .#hostname \
  --target-host xeseuses@<ip> --use-remote-sudo
```

**Provision a new machine:**

```bash
# 1. Boot target from vanallenbelt USB
# 2. From WSL:
nix run .#xesh-bootstrap -- \
  --hostname <newhost> \
  --target <ip> \
  --age-key /path/to/age-key.txt

# 3. After first boot:
nix run /home/xeseuses/nixos-infra#xesh-postinstall
```

**Secrets:**

```bash
sops secrets/secrets.yaml             # Edit (auto-decrypts)
sops updatekeys secrets/secrets.yaml  # Re-encrypt after adding a host key
```

**Build installer ISOs:**

```bash
# Installer ISO
nix build .#nixosConfigurations.vanallenbelt.config.system.build.isoImage --print-out-paths

# Keygen ISO (air-gapped age key generation)
nix build .#nixosConfigurations.kepler.config.system.build.isoImage --print-out-paths
```

---

## Security

- Secrets encrypted with SOPS + age, never plaintext in git
- SSH key-only auth, password login disabled everywhere
- Full disk encryption on mobile hosts (vela)
- nftables default-drop on the router
- All external services tunneled over WireGuard — zero open ports at home
- endlessh SSH tarpit + honeypots on lyra
- CrowdSec collaborative IPS with nftables bouncer
- AdGuardHome DNS blocking on all VLANs

---

## References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Disko](https://github.com/nix-community/disko)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [Swarsel/.dotfiles](https://swarsel.github.io/.dotfiles/) — architecture inspiration

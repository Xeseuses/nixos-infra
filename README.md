# NixOS Infrastructure

My fully declarative NixOS homelab — constellation-themed hosts, managed entirely as code.

## 🏗️ Design Principles

- **Declarative** — Everything in Nix. No manual configuration, no snowflakes
- **Reproducible** — Same config = same system, every time
- **Version controlled** — All changes tracked in git, secrets encrypted
- **Modular** — Reusable modules across machines via `asthrossystems.*` options
- **Self-hosted** — DNS, DHCP, VPN, reverse proxy, monitoring all in-house

---

## 🖥️ Fleet

| Hostname | Hardware | Role | Status |
|----------|----------|------|--------|
| **orion** | Protectli VP2420 | Router — VLANs, nftables, Kea DHCP, AdGuard, NSD | ✅ Live |
| **eridanus** | Beelink EQ12 (N100, 16GB) | Binary cache (harmonia), backups | ✅ Live |
| **caelum** | Beelink EQ12 | Immich, Audiobookshelf, Solibieb | ✅ Live |
| **andromeda** | Beelink EQ12 | Home Assistant VM host (libvirt) | ✅ Live |
| **horologium** | Custom (i5-13500, 16GB, ZFS) | Media server — Jellyfin, Arr stack | ✅ Live |
| **lyra** | Hetzner CX23 VPS | Caddy reverse proxy, WireGuard hub, honeypot | ✅ Live |
| **vela** | ASUS ROG Flow Z13 | Encrypted laptop — Niri desktop | ✅ Live |
| **vega** | Minisforum SER8 | Desktop (dual-boot, planned) | 📅 Planned |

---

## 🌐 Network

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

**WireGuard topology** (hub: lyra `10.200.0.1`):
```
lyra (hub)
├── orion      10.200.0.6  — gateway to all home VLANs
├── andromeda  10.200.0.2  — HA proxy
├── caelum     10.200.0.3  — services
├── vela       10.200.0.4  — laptop road warrior
└── phone      10.200.0.5  — GrapheneOS road warrior
```

**DNS stack** (all on orion):
```
clients → AdGuardHome :53 (blocklists, per-client rules, query log)
               ↓
          Unbound :5335 (DNSSEC, DoT to Quad9)
               ↓
           NSD :5354 (authoritative: lan. + xesh.cc split-horizon)
```

**Public services** via lyra + WireGuard:

| Domain | Service | Host |
|--------|---------|------|
| `ha.xesh.cc` | Home Assistant | andromeda |
| `immich.xesh.cc` | Immich photo library | caelum |
| `audiobooks.xesh.cc` | Audiobookshelf | caelum |
| `solibieb.nl` | Django web app | caelum |
| `threats.xesh.cc` | Honeypot dashboard (WireGuard only) | lyra |

**Honeypot** (lyra):
- Port 22 → endlessh-go SSH tarpit
- Port 22022 → real SSH
- Ports 21, 23, 3306 → fake FTP/telnet/MySQL honeypots
- CrowdSec with nftables bouncer

---

## 📁 Repository Structure

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
│           ├── backup.nix        # Restic backups
│           ├── binary-cache.nix  # nix-serve / harmonia
│           ├── impermanence.nix  # Ephemeral root (desktop)
│           └── impermanence-server.nix  # Ephemeral root (server)
├── hosts/
│   ├── orion/                    # Router config
│   │   ├── adguardhome.nix
│   │   ├── nsd.nix
│   │   ├── unbound.nix
│   │   └── wireguard.nix
│   ├── lyra/                     # VPS
│   │   ├── honeypot.nix
│   │   ├── crowdsec.nix
│   │   └── dashboard.nix
│   ├── eridanus/                 # Binary cache
│   ├── caelum/                   # Services
│   ├── andromeda/                # HA host
│   ├── horologium/               # Media server
│   └── vela/                     # Laptop
└── pkgs/
    ├── xesh-bootstrap/           # nixos-anywhere wrapper
    └── xesh-postinstall/         # First-boot helper
```

---

## 🚀 Usage

### Deploy to a host
```bash
# Locally (on the machine)
sudo nixos-rebuild switch --flake .#hostname

# Remotely from WSL/another machine
nixos-rebuild switch --flake .#hostname \
  --target-host xeseuses@<ip> --use-remote-sudo
```

### Provision a new machine
```bash
# 1. Boot target from vanallenbelt USB (installer ISO)
# 2. From WSL:
nix run .#xesh-bootstrap -- \
  --hostname <newhost> \
  --target <ip> \
  --age-key /path/to/age-key.txt

# 3. After first boot on new machine:
nix run /home/xeseuses/nixos-infra#xesh-postinstall
```

### Manage secrets
```bash
sops secrets/secrets.yaml              # Edit secrets (auto-decrypts)
sops updatekeys secrets/secrets.yaml   # Re-encrypt after adding a new host key
```

### Build installer ISOs
```bash
# Installer ISO (boot on target hardware)
nix build .#nixosConfigurations.vanallenbelt.config.system.build.isoImage --print-out-paths

# Keygen ISO (air-gapped age key generation)
nix build .#nixosConfigurations.kepler.config.system.build.isoImage --print-out-paths
```

---

## 🔐 Security

- Secrets encrypted with SOPS + age keys (never plaintext in git)
- SSH key-only authentication, password auth disabled
- Full disk encryption on mobile hosts (vela)
- nftables default-drop firewall on router
- WireGuard for all external service exposure — no ports open at home
- endlessh SSH tarpit + honeypots on lyra
- CrowdSec collaborative IPS with nftables bouncer
- AdGuardHome DNS-level ad/tracker blocking on all VLANs

---

## 📚 References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Disko](https://github.com/nix-community/disko)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [Swarsel/.dotfiles](https://swarsel.github.io/.dotfiles/) — architecture inspiration

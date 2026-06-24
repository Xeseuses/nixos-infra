# NixOS Infrastructure

My fully declarative NixOS homelab — constellation-themed hosts, managed entirely as code.

## 🏗️ Design Principles

- **Declarative** — Everything in Nix. No manual configuration, no snowflakes
- **Reproducible** — Same config = same system, every time
- **Version controlled** — All changes tracked in git, secrets encrypted
- **Modular** — Reusable modules across machines via `asthrossystems.*` options
- **Self-hosted** — DNS, DHCP, VPN, reverse proxy, file sync, monitoring all in-house
- **Defended** — Active honeypots, auto-banning, file integrity monitoring, audit logging

---

## 🖥️ Fleet

| Hostname | Hardware | Role | Status |
|----------|----------|------|--------|
| **orion** | Protectli VP2420 | Router — VLANs, nftables, Kea DHCP, AdGuard, NSD | ✅ Live |
| **eridanus** | Beelink EQ12 (N100, 16GB) | Nextcloud, binary cache, security dashboard | ✅ Live |
| **caelum** | Beelink EQ12 | Immich, Audiobookshelf, Solibieb, UniFi | ✅ Live |
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
├── orion      10.200.0.6  — gateway to all home VLANs (resilient — always on)
├── andromeda  10.200.0.2  — HA proxy only
├── caelum     10.200.0.3  — services
├── eridanus   10.200.0.7  — Nextcloud proxy
├── vela       10.200.0.4  — laptop road warrior (full home access)
└── phone      10.200.0.5  — GrapheneOS road warrior (full home access)
```
> Security note: lyra only knows WireGuard IPs directly. Home VLAN routing
> is handled by orion (always-on router), not by any single service host —
> eliminates single point of failure for road warrior connectivity.

**DNS stack** (all on orion):
```
clients → AdGuardHome :53 (4 blocklists, named clients, per-group filtering)
               ↓
          Unbound :5335 (DNSSEC validation, DoT to Quad9)
               ↓
           NSD :5354 (authoritative: lan. + xesh.cc split-horizon)
```
- 32MB cache, 30-day query log & stats retention
- Named clients for all 14+ known devices (servers get relaxed filtering, IoT gets strict)
- Blocklists: AdGuard DNS filter, Steven Black, OISD full, HaGeZi Pro++

**Public services** via lyra + WireGuard (TLS via Caddy/Let's Encrypt):

| Domain | Service | Host |
|--------|---------|------|
| `ha.xesh.cc` | Home Assistant | andromeda |
| `immich.xesh.cc` | Immich photo library | caelum |
| `audiobooks.xesh.cc` | Audiobookshelf | caelum |
| `solibieb.nl` | Django web app | caelum |
| `cloud.xesh.cc` | Nextcloud (files, calendar, contacts) | eridanus |
| `threats.xesh.cc` | Honeypot dashboard (internal access only) | lyra |

**Internal-only services** (WireGuard / home network):

| Domain | Service | Host |
|--------|---------|------|
| `security.lan:8090` | Security monitoring dashboard | eridanus |
| `orion.lan:3000` | AdGuardHome web UI | orion |
| `orion.lan:9090` | Kea DHCP lease viewer | orion |

---

## 🛡️ Security

### Perimeter defense (lyra)
- **endlessh-go** SSH tarpit on port 22 — infinite banner loop traps bots indefinitely
- **Honeypot services** — fake FTP (21), telnet (23), MySQL (3306); logs + immediately identifies scanners
- **CrowdSec** — collaborative IPS with nftables bouncer
- **Auto-ban** — any IP hitting honeypot services 3+ times in 24h gets banned for 7 days automatically
- **Threat dashboard** (`threats.xesh.cc`) — live stats, auto-ban activity, top attackers, all auto-refreshing every 5 min

### Host-level monitoring (orion, eridanus, caelum, andromeda, horologium)
- **auditd** — kernel-level audit: identity/sudoers changes, SSH config, privilege escalation, Nix store writes, kernel module loading, time changes
- **AIDE** — daily file integrity check (02:30) on `/etc`, `/boot`, SOPS secrets, SSH host keys
- **Security dashboard** (`security.lan:8090`) — aggregates auditd + AIDE from all 5 monitored hosts via SSH, refreshes every 15 min
- *(lyra intentionally excluded — VPS threat model differs; perimeter defense via CrowdSec is the right layer there, not host auditing)*

### Network
- nftables default-drop firewall on router
- WireGuard for all external service exposure — no inbound ports open at home
- Full disk encryption on mobile hosts (vela)
- SSH key-only authentication, password auth disabled
- Secrets encrypted with SOPS + age keys (never plaintext in git)

---

## ☁️ Self-hosted services

- **Nextcloud** (eridanus) — file sync, calendar (CalDAV), contacts (CardDAV), notes, tasks. PostgreSQL + Redis backend.
- **Immich** (caelum, Docker) — photo/video library with ML search
- **Home Assistant** (andromeda, VM) — home automation
- **Audiobookshelf** (caelum) — audiobook server
- **Jellyfin + Arr stack** (horologium) — media server, ZFS-backed
- **UniFi Network Application** (caelum, Docker) — AP/network management

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
│       ├── common/                # Loaded on every host
│       │   ├── nix.nix            # Binary cache, GC, flakes
│       │   ├── ssh.nix
│       │   ├── users.nix
│       │   ├── locale.nix
│       │   └── networking.nix
│       └── optional/              # Feature modules
│           ├── backup.nix         # Restic backups
│           ├── binary-cache.nix   # nix-serve / harmonia
│           ├── hardening.nix      # auditd + AIDE (servers, not lyra)
│           ├── impermanence.nix         # Ephemeral root (desktop)
│           └── impermanence-server.nix  # Ephemeral root (server)
├── hosts/
│   ├── orion/                     # Router
│   │   ├── adguardhome.nix        # DNS frontend, named clients, blocklists
│   │   ├── nsd.nix                # Authoritative DNS, split-horizon
│   │   ├── unbound.nix            # Recursive resolver, DNSSEC, DoT
│   │   └── wireguard.nix          # Home VLAN gateway peer
│   ├── lyra/                      # VPS
│   │   ├── honeypot.nix           # endlessh + fake services
│   │   ├── crowdsec.nix           # IPS, custom honeypot parser/scenario
│   │   ├── dashboard.nix          # Threat dashboard service + timer
│   │   └── generate-dashboard.py  # Auto-ban + HTML generation
│   ├── eridanus/                  # Nextcloud + binary cache + security hub
│   │   ├── nextcloud.nix
│   │   ├── wireguard.nix
│   │   ├── security-dashboard.nix
│   │   └── generate-security-dashboard.py
│   ├── caelum/                    # Services (Immich, Audiobookshelf, Solibieb)
│   ├── andromeda/                 # HA host
│   ├── horologium/                # Media server
│   └── vela/                      # Laptop
└── pkgs/
    ├── xesh-bootstrap/            # nixos-anywhere wrapper
    └── xesh-postinstall/          # First-boot helper
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

### Manual security operations
```bash
# Ban an IP immediately on lyra (don't wait for auto-ban)
sudo cscli -c $(ls /nix/store/*-crowdsec.yaml | head -1) decisions add \
  --ip 1.2.3.4 --duration 24h --reason "manual ban"

# List active bans
sudo cscli -c $(ls /nix/store/*-crowdsec.yaml | head -1) decisions list

# Trigger dashboard regeneration
sudo systemctl start honeypot-dashboard     # on lyra
sudo systemctl start security-dashboard     # on eridanus
```

### Build installer ISOs
```bash
# Installer ISO (boot on target hardware)
nix build .#nixosConfigurations.vanallenbelt.config.system.build.isoImage --print-out-paths

# Keygen ISO (air-gapped age key generation)
nix build .#nixosConfigurations.kepler.config.system.build.isoImage --print-out-paths
```

---

## 📚 References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Disko](https://github.com/nix-community/disko)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [CrowdSec](https://www.crowdsec.net/) — collaborative IPS
- [AIDE](https://aide.github.io/) — file integrity monitoring
- [Swarsel/.dotfiles](https://swarsel.github.io/.dotfiles/) — architecture inspiration


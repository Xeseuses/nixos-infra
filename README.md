# NixOS Infrastructure

My fully declarative NixOS homelab, managed as code using flakes.

## 🏗️ Architecture

### Design Principles
- **Declarative**: Everything defined in Nix — no manual configuration
- **Reproducible**: Same config = same system, every time
- **Version Controlled**: All changes tracked in git
- **Encrypted Secrets**: SOPS with age encryption
- **Modular**: Reusable modules across machines

### Technology Stack
- **NixOS 26.05**: Base operating system
- **Flakes**: Dependency management and reproducibility
- **SOPS**: Secret management
- **Disko**: Declarative disk partitioning
- **Restic**: Automated backups
- **WireGuard**: VPN tunnels between home and VPS
- **Caddy**: Automatic HTTPS reverse proxy

---

## 🖥️ Fleet

Hosts named after constellations and celestial objects:

| Hostname | Hardware | Role | Status |
|----------|----------|------|--------|
| **orion** | Protectli VP2420 | NixOS Router (VLANs, nftables, Kea DHCP) | ✅ Live |
| **eridanus** | Beelink EQ12 | Binary cache + backups | ✅ Live |
| **vela** | ASUS ROG Flow Z13 | Encrypted laptop (Niri desktop) | ✅ Live |
| **andromeda** | Beelink EQ12 | Home Assistant VM host | ✅ Live |
| **caelum** | Beelink EQ12 | Immich, Audiobookshelf, Solibieb | ✅ Live |
| **lyra** | RackNerd VPS | Caddy reverse proxy + WireGuard server | ✅ Live |
| **horologium** | Custom (i5-13500, RTX 3060) | Jellyfin, Arr stack, ZFS storage | 📅 Planned |
| **vega** | Minisforum SER8 | Gaming PC (dual-boot) | 📅 Planned |

---

## 🌐 Network

```
Internet → FritzBox → orion (NixOS Router) → Mikrotik Switch
                           ↓
              VLANs: 10 (LAN) · 20 (Guest) · 30 (Management)
                     40 (Servers) · 50 (IoT) · 99 (Quarantine)
```

**Public services** (via lyra VPS + WireGuard tunnel):

| Domain | Service |
|--------|---------|
| ha.xesh.cc | Home Assistant |
| immich.xesh.cc | Immich (photos) |
| audiobooks.xesh.cc | Audiobookshelf |
| solibieb.nl | Django web app |

**Firewall policy** (nftables, default-drop):
- Management + LAN → anywhere (trusted)
- Servers → WAN + IoT
- IoT + Guest → WAN only
- HA VM → specific sensor pinholes on Management VLAN

---

## 📁 Structure

```
nixos-infra/
├── flake.nix                 # All hosts defined here
├── flake.lock
├── .sops.yaml                # Age key configuration
├── secrets/
│   └── secrets.yaml          # Encrypted with SOPS
├── modules/
│   ├── options.nix           # Custom asthrossystems.* options
│   └── nixos/
│       ├── common/           # Loaded on every host
│       └── optional/         # Feature modules (backup, impermanence, etc.)
└── hosts/
    ├── orion/                # Router
    ├── eridanus/             # Binary cache
    ├── vela/                 # Laptop
    ├── andromeda/            # HA host
    └── caelum/               # Services
```

---

## 🚀 Usage

### Deploy to a host
```bash
# Locally
sudo nixos-rebuild switch --flake .#hostname

# Remotely
nixos-rebuild switch --flake .#hostname \
  --target-host user@host --use-remote-sudo
```

### Add a new machine
1. Create `hosts/newhost/` with `default.nix` and `disk-config.nix`
2. Add to `flake.nix`
3. Generate age key on machine, add to `.sops.yaml`
4. Re-encrypt: `sops updatekeys secrets/secrets.yaml`
5. Deploy!

### Manage secrets
```bash
sops secrets/secrets.yaml        # Edit (auto-decrypts)
sops updatekeys secrets/secrets.yaml  # Add new machine key
```

---

## 🔐 Security

- Secrets encrypted with SOPS + age (never plaintext in git)
- SSH key-only authentication
- Full disk encryption on mobile hosts (vela)
- nftables default-drop firewall on router
- WireGuard for all external service exposure (no open ports at home)

---

## 📚 References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Disko](https://github.com/nix-community/disko)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [SwarselSystems](https://github.com/Swarsel/nixos-config) — architecture inspiration
- [ruiiiijiiiiang/nixos-config](https://github.com/ruiiiijiiiiang/nixos-config) — router + nftables inspiration


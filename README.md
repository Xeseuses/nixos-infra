# NixOS Infrastructure

My declarative NixOS infrastructure using flakes, managed as code.

## 🏗️ Architecture

### Design Principles
- **Declarative**: Everything defined in Nix
- **Reproducible**: Same config = same system
- **Version Controlled**: All config in git
- **Encrypted Secrets**: Using SOPS with age
- **Modular**: Reusable modules across machines

### Technology Stack
- **NixOS 24.11**: Base operating system
- **Flakes**: For dependency management
- **SOPS**: Secret management
- **Disko**: Declarative disk partitioning
- **Restic**: Automated backups

## 🖥️ Infrastructure

### Naming Convention
Hosts named after constellations and celestial objects:

| Hostname | Type | Hardware | Role |
|----------|------|----------|------|
| **Orion** | Router | Protectli Vault 4W4C | Network gateway, VLANs, IPv6 tunnel |
| **Andromeda** | Server | Beelink EQ12 (16GB) | Immich, Audiobookshelf, Django |
| **Caelum** | Server | Beelink EQ12 (16GB) | Spare |
| **Eridanus** | Server | Beelink EQ12 (16GB) | Testing / Development |
| **Horologium** | Server | Custom (i5-13500, RTX 3060, 16GB, 4x2TB SSD) | ZFS storage, MicroVMs (HA, Arr stack), Jellyfin |
| **lyra** | VPS | Racknerd | Caddy reverse proxy |
| **Pavo** | Desktop | Minisforum SER 8 (Ryzen 7 8745HS) | Gaming PC (dual-boot Windows) |
| **Vela** | Laptop | TBD | Mobile workstation |

### Network Topology
```
Internet → FritzBox (Modem) → orion (NixOS Router) → Mikrotik Switch
                                          ↓
                        VLANs: 10 (Server), 20 (Guest), 30 (Management), 40 (IoT)
```

**IPv6**: Hurricane Electric tunnel (2001:470:xxxx::/48)

**VPN**: Management + Guest VLANs route through Mullvad

## 📁 Repository Structure
```
nixos-infra/
├── flake.nix                 # Main flake configuration
├── flake.lock               # Locked dependencies
├── .sops.yaml               # SOPS configuration
├── README.md
│
├── secrets/
│   └── secrets.yaml         # Encrypted secrets (SOPS)
│
├── modules/
│   ├── options.nix          # Custom option declarations
│   │
│   └── nixos/
│       ├── common/          # Shared across all machines
│       │   ├── default.nix  # Imports all common modules
│       │   ├── nix.nix      # Nix daemon settings
│       │   ├── ssh.nix      # SSH configuration
│       │   ├── users.nix    # User management
│       │   ├── locale.nix   # Timezone/locale
│       │   └── networking.nix  # Basic networking
│       │
│       ├── server/          # Server-specific common config
│       │
│       └── optional/        # Feature modules
│           └── backup.nix   # Restic backup configuration
│
└── hosts/
    ├── eridanus/
    │   ├── default.nix      # Host configuration
    │   └── disk-config.nix  # Disko disk layout
    ├── andromeda/
    ├── horologium/
    └── ...
```

## 🚀 Usage

### Deploy to a Machine
```bash
# From local machine (or on the target machine)
cd ~/nixos-infra

# Pull latest changes
git pull

# Rebuild system
sudo nixos-rebuild switch --flake .#hostname

# Or deploy remotely
nixos-rebuild switch --flake .#eridanus \
  --target-host username@eridanus \
  --use-remote-sudo
```

### Add a New Machine

1. Create host directory: `hosts/newhost/`
2. Add `default.nix` and `disk-config.nix`
3. Generate age key on the machine
4. Add age key to `.sops.yaml`
5. Re-encrypt secrets: `sops updatekeys secrets/secrets.yaml`
6. Add to `flake.nix`
7. Deploy!

### Manage Secrets
```bash
# Edit secrets (decrypts automatically)
sops secrets/secrets.yaml

# Add new machine key
sops updatekeys secrets/secrets.yaml
```

### Backups
```bash
# List backups
sudo restic -r /var/backups/restic/system snapshots

# Restore specific file
sudo restic -r /var/backups/restic/system restore latest \
  --target /tmp/restore \
  --path /specific/file

# Manual backup
sudo systemctl start restic-backups-system.service
```

## 🔐 Security

- **Secrets**: Encrypted with SOPS (age encryption)
- **SSH**: Key-based authentication only
- **Sudo**: Passwordless for wheel group (convenience on home network)
- **Firewall**: Enabled on all machines
- **Updates**: Automatic security updates enabled

## 🛠️ Technologies Used

### Core
- **NixOS**: Declarative Linux distribution
- **Nix Flakes**: Reproducible dependency management
- **Home Manager**: User environment management (future)

### Infrastructure
- **Disko**: Declarative disk partitioning
- **SOPS**: Secret management with age encryption
- **Restic**: Incremental backups

### Services (Planned)
- **ZFS**: RAID10 storage with snapshots
- **MicroVMs**: Isolated service containers
- **Caddy**: Reverse proxy
- **WireGuard**: VPN tunnels

## 📚 Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [Disko](https://github.com/nix-community/disko)
- [SwarselSystems](https://github.com/Swarsel/nixos-config) (inspiration)

## 📄 License

Personal infrastructure - not licensed for reuse.

## 🙏 Acknowledgments

- NixOS community
- SwarselSystems for architecture inspiration

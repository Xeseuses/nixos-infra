# Run from WSL / any existing machine with nix:
#   nix run .#xesh-bootstrap -- --hostname vega --target 10.40.40.XXX --age-key /path/to/age-key.txt
#
# What it does:
#   1. Reads asthrossystems.storage.rootDisk from the target's flake config
#   2. Reads asthrossystems.features.encryption to decide LUKS flow
#   3. Injects the age private key to /var/lib/sops-nix/key.txt on the target
#   4. Calls nixos-anywhere which runs disko + nixos-install remotely
#   5. Machine reboots into your full config

{ pkgs, nixos-anywhere, ... }:

pkgs.writeShellApplication {
  name = "xesh-bootstrap";

  runtimeInputs = with pkgs; [
    nixos-anywhere   # the real workhorse
    nix              # nix eval to read flake options
    jq               # parse JSON from nix eval
    openssh          # ssh-keyscan for host key verification
    age              # verify age key is valid before we start
    coreutils
  ];

  text = ''
    # ── Colours ─────────────────────────────────────────────────────────────
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
    green()  { echo -e "''${GREEN}==> $*''${NC}"; }
    yellow() { echo -e "''${YELLOW}==> $*''${NC}"; }
    red()    { echo -e "''${RED}==> ERROR: $*''${NC}"; }
    bold()   { echo -e "''${BOLD}$*''${NC}"; }

    # ── Usage ────────────────────────────────────────────────────────────────
    usage() {
      bold "xesh-bootstrap — remote NixOS installer for constellation hosts"
      echo ""
      echo "  Usage: nix run .#xesh-bootstrap -- [OPTIONS]"
      echo ""
      echo "  Required:"
      echo "    -n, --hostname <name>      NixOS configuration name (e.g. vega)"
      echo "    -d, --target   <ip>        IP address of the target machine"
      echo "    -k, --age-key  <path>      Path to the age PRIVATE key file"
      echo ""
      echo "  Optional:"
      echo "    -p, --ssh-port <port>      SSH port on target (default: 22)"
      echo "    -u, --ssh-user <user>      SSH user on target (default: root)"
      echo "    -f, --flake    <path>      Path to flake (default: .)"
      echo "        --dry-run              Show what would happen, don't install"
      echo "        --debug                Enable set -x and nixos-anywhere --debug"
      echo "    -h, --help                 Show this message"
      echo ""
      echo "  Example:"
      echo "    nix run .#xesh-bootstrap -- -n vega -d 10.40.40.50 -k ~/keys/vega-age.txt"
    }

    # ── Argument parsing ─────────────────────────────────────────────────────
    TARGET_HOSTNAME=""
    TARGET_IP=""
    AGE_KEY_PATH=""
    SSH_PORT="22"
    SSH_USER="root"
    FLAKE_PATH="."
    DRY_RUN=false
    DEBUG=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -n|--hostname) TARGET_HOSTNAME="$2"; shift 2 ;;
        -d|--target)   TARGET_IP="$2";       shift 2 ;;
        -k|--age-key)  AGE_KEY_PATH="$2";    shift 2 ;;
        -p|--ssh-port) SSH_PORT="$2";        shift 2 ;;
        -u|--ssh-user) SSH_USER="$2";        shift 2 ;;
        -f|--flake)    FLAKE_PATH="$2";      shift 2 ;;
        --dry-run)     DRY_RUN=true;         shift ;;
        --debug)       DEBUG=true; set -x;   shift ;;
        -h|--help)     usage; exit 0 ;;
        *) red "Unknown option: $1"; usage; exit 1 ;;
      esac
    done

    # ── Validate required args ────────────────────────────────────────────────
    if [[ -z "$TARGET_HOSTNAME" || -z "$TARGET_IP" || -z "$AGE_KEY_PATH" ]]; then
      red "--hostname, --target, and --age-key are all required."
      echo ""
      usage
      exit 1
    fi

    bold ""
    bold "╔══════════════════════════════════════════════════════════════╗"
    bold "║          xesh-bootstrap — constellation installer           ║"
    bold "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    green "Target hostname : $TARGET_HOSTNAME"
    green "Target IP       : $TARGET_IP"
    green "Age key         : $AGE_KEY_PATH"
    green "SSH             : $SSH_USER@$TARGET_IP:$SSH_PORT"
    green "Flake           : $FLAKE_PATH"
    echo ""

    # ── Pre-flight checks ────────────────────────────────────────────────────
    green "Running pre-flight checks..."

    # 1. Age key must exist and be readable
    if [[ ! -f "$AGE_KEY_PATH" ]]; then
      red "Age key not found: $AGE_KEY_PATH"
      exit 1
    fi
    if ! age-keygen -y "$AGE_KEY_PATH" &>/dev/null; then
      red "File $AGE_KEY_PATH does not look like a valid age private key."
      exit 1
    fi
    green "Age key OK"

    # 2. Target hostname must exist in the flake
    FLAKE_CONFIG="$FLAKE_PATH#nixosConfigurations.$TARGET_HOSTNAME"
    if ! nix eval "$FLAKE_PATH#nixosConfigurations" --apply "cfg: builtins.hasAttr \"$TARGET_HOSTNAME\" cfg" 2>/dev/null | grep -q "true"; then
      red "No nixosConfiguration named '$TARGET_HOSTNAME' found in $FLAKE_PATH"
      echo "  Available configurations:"
      nix eval "$FLAKE_PATH#nixosConfigurations" --apply builtins.attrNames 2>/dev/null || true
      exit 1
    fi
    green "Flake config '$TARGET_HOSTNAME' found"

    # 3. Read asthrossystems options from the target config
    green "Reading host config from flake..."

    ROOT_DISK=$(nix eval --raw \
      "$FLAKE_PATH#nixosConfigurations.$TARGET_HOSTNAME.config.asthrossystems.storage.rootDisk" \
      2>/dev/null || echo "")

    IS_ENCRYPTED=$(nix eval \
      "$FLAKE_PATH#nixosConfigurations.$TARGET_HOSTNAME.config.asthrossystems.features.encryption" \
      2>/dev/null || echo "false")

    if [[ -z "$ROOT_DISK" ]]; then
      red "Could not read asthrossystems.storage.rootDisk from $TARGET_HOSTNAME config."
      red "Make sure the host has asthrossystems.storage.rootDisk set (e.g. \"/dev/nvme0n1\")."
      exit 1
    fi

    green "Root disk    : $ROOT_DISK"
    green "Encrypted    : $IS_ENCRYPTED"

    # 4. Target must be reachable over SSH
    green "Checking SSH connectivity to $TARGET_IP:$SSH_PORT..."
    if ! ssh -p "$SSH_PORT" \
         -o ConnectTimeout=10 \
         -o StrictHostKeyChecking=no \
         -o BatchMode=yes \
         "$SSH_USER@$TARGET_IP" true 2>/dev/null; then
      red "Cannot SSH to $SSH_USER@$TARGET_IP:$SSH_PORT"
      echo "  Is the machine booted into Drugstore?"
      echo "  Is your SSH public key baked into hosts/vanallenbelt/default.nix?"
      echo "  Try: ssh -p $SSH_PORT $SSH_USER@$TARGET_IP"
      exit 1
    fi
    green "SSH connection OK"

    # ── Summary before proceeding ─────────────────────────────────────────────
    echo ""
    bold "About to install:"
    echo "  Hostname    : $TARGET_HOSTNAME"
    echo "  Target IP   : $TARGET_IP"
    echo "  Root disk   : $ROOT_DISK  (disko will WIPE this)"
    echo "  Encryption  : $IS_ENCRYPTED"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
      yellow "DRY RUN — stopping here. Remove --dry-run to proceed."
      exit 0
    fi

    # This is destructive — require explicit confirmation
    yellow "This will WIPE $ROOT_DISK on $TARGET_IP and install NixOS."
    echo -n "Type 'yes' to continue: "
    read -r CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
      red "Aborted."
      exit 1
    fi

    # ── Prepare age key injection ─────────────────────────────────────────────
    # nixos-anywhere's --extra-files copies a local directory tree into / on
    # the installed system. We create a temp dir matching the target path layout.
    EXTRA_FILES_DIR=$(mktemp -d)
    trap 'rm -rf "$EXTRA_FILES_DIR"' EXIT

    # Your SOPS config uses: sops.age.keyFile = "/var/lib/sops-nix/key.txt"
    AGE_DEST_DIR="$EXTRA_FILES_DIR/var/lib/sops-nix"
    mkdir -p "$AGE_DEST_DIR"
    cp "$AGE_KEY_PATH" "$AGE_DEST_DIR/key.txt"
    chmod 600 "$AGE_DEST_DIR/key.txt"
    # nixos-anywhere --chown will set ownership to root:root (default) which is correct

    green "Age key staged for injection → /var/lib/sops-nix/key.txt"

    # ── Build nixos-anywhere flags ────────────────────────────────────────────
    NIXOS_ANYWHERE_ARGS=(
      --flake "$FLAKE_PATH#$TARGET_HOSTNAME"
      --target-host "$SSH_USER@$TARGET_IP"
      --ssh-port "$SSH_PORT"
      --extra-files "$EXTRA_FILES_DIR"
      # Disable SSH host key checking — we're installing a fresh system,
      # the host keys are about to be regenerated anyway
      --ssh-option "StrictHostKeyChecking=no"
      --ssh-option "UserKnownHostsFile=/dev/null"
    )

    # Handle LUKS — nixos-anywhere can pass the disk encryption password
    # before disko runs so LUKS setup is fully automated
    if [[ "$IS_ENCRYPTED" == "true" ]]; then
      yellow "Encryption is enabled. You'll be prompted for a LUKS password."
      echo "This password will be needed on every boot."
      echo -n "Enter LUKS password: "
      read -rs LUKS_PASSWORD
      echo ""
      echo -n "Confirm LUKS password: "
      read -rs LUKS_PASSWORD_CONFIRM
      echo ""
      if [[ "$LUKS_PASSWORD" != "$LUKS_PASSWORD_CONFIRM" ]]; then
        red "Passwords do not match."
        exit 1
      fi
      # Write to a temp file and pass via --disk-encryption-keys
      LUKS_KEY_FILE=$(mktemp)
      echo -n "$LUKS_PASSWORD" > "$LUKS_KEY_FILE"
      trap 'rm -rf "$EXTRA_FILES_DIR" "$LUKS_KEY_FILE"' EXIT
      NIXOS_ANYWHERE_ARGS+=(
        --disk-encryption-keys /tmp/disko-password "$LUKS_KEY_FILE"
      )
    fi

    if [[ "$DEBUG" == "true" ]]; then
      NIXOS_ANYWHERE_ARGS+=( --debug )
    fi

    # ── Run nixos-anywhere ────────────────────────────────────────────────────
    echo ""
    green "Starting nixos-anywhere..."
    green "This will: kexec into NixOS minimal → disko → nixos-install → reboot"
    echo ""

    nixos-anywhere "''${NIXOS_ANYWHERE_ARGS[@]}"

    # ── Post-install ──────────────────────────────────────────────────────────
    echo ""
    bold "╔══════════════════════════════════════════════════════════════╗"
    bold "║  Installation complete! Machine is rebooting.               ║"
    bold "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Next steps:"
    echo ""
    echo "  1. Wait ~30s for the machine to come up, then:"
    echo "     ssh xeseuses@$TARGET_IP"
    echo ""
    echo "  2. On the new machine, run post-install:"
    echo "     nix run /home/xeseuses/nixos-infra#xesh-postinstall"
    echo ""
    echo "  3. Things to do after that:"
    echo "     □  git add hosts/$TARGET_HOSTNAME/hardware-configuration.nix"
    echo "     □  git commit -m 'feat: add $TARGET_HOSTNAME'"
    echo "     □  git push"
    echo "     □  Add $TARGET_HOSTNAME to nightly builder on horologium"
    echo "     □  Verify restic backup is configured"
    echo "     □  Add WireGuard peer to lyra if needed"
    echo ""
  '';
}


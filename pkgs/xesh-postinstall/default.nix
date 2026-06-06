# Run ON the newly installed machine after first boot:
#   nix run /home/xeseuses/nixos-infra#xesh-postinstall
#
# What it does:
#   1. Verifies SOPS secrets decrypt correctly (age key is working)
#   2. Clones the flake if not already present
#   3. Generates hardware-configuration.nix and adds it to the repo
#   4. Prompts to git push
#   5. Prints the post-install checklist

{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "xesh-postinstall";

  runtimeInputs = with pkgs; [
    git
    nix
    sops
    age
    openssh
    coreutils
    gnugrep
  ];

  text = ''
    # ── Colours ─────────────────────────────────────────────────────────────
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BOLD='\033[1m'; NC='\033[0m'
    green()  { echo -e "''${GREEN}==> $*''${NC}"; }
    yellow() { echo -e "''${YELLOW}==> $*''${NC}"; }
    red()    { echo -e "''${RED}==> ERROR: $*''${NC}"; }
    bold()   { echo -e "''${BOLD}$*''${NC}"; }
    ok()     { echo -e "''${GREEN}  ✓ $*''${NC}"; }
    fail()   { echo -e "''${RED}  ✗ $*''${NC}"; }
    skip()   { echo -e "''${YELLOW}  - $*''${NC}"; }

    HOSTNAME=$(hostname)
    FLAKE_DIR="/home/xeseuses/nixos-infra"
    FLAKE_REPO="git@github.com:xeseuses/nixos-infra.git"   # ← your GitHub repo
    AGE_KEY_FILE="/var/lib/sops-nix/key.txt"
    SECRETS_FILE="$FLAKE_DIR/secrets/secrets.yaml"

    bold ""
    bold "╔══════════════════════════════════════════════════════════════╗"
    bold "║       xesh-postinstall — first boot setup for $HOSTNAME"
    bold "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    CHECKS_PASSED=true

    # ── Check 1: Age key present ──────────────────────────────────────────────
    green "Checking age key..."
    if [[ -f "$AGE_KEY_FILE" ]]; then
      ok "Age key present at $AGE_KEY_FILE"
    else
      fail "Age key MISSING at $AGE_KEY_FILE"
      echo "     The bootstrap script should have injected this."
      echo "     If you installed manually, copy your private key:"
      echo "     sudo mkdir -p /var/lib/sops-nix"
      echo "     sudo cp /path/to/your/age-key.txt $AGE_KEY_FILE"
      echo "     sudo chmod 600 $AGE_KEY_FILE"
      CHECKS_PASSED=false
    fi

    # ── Check 2: Flake repo present ───────────────────────────────────────────
    green "Checking flake repo..."
    if [[ -d "$FLAKE_DIR/.git" ]]; then
      ok "Flake already cloned at $FLAKE_DIR"
    else
      yellow "Flake not found at $FLAKE_DIR — cloning..."
      if git clone "$FLAKE_REPO" "$FLAKE_DIR"; then
        ok "Flake cloned to $FLAKE_DIR"
      else
        fail "Could not clone $FLAKE_REPO"
        echo "     Check your SSH key is added to GitHub:"
        echo "     ssh -T git@github.com"
        CHECKS_PASSED=false
      fi
    fi

    # ── Check 3: SOPS secrets decrypt ────────────────────────────────────────
    green "Checking SOPS secret decryption..."
    if [[ -f "$SECRETS_FILE" ]]; then
      if SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" sops --decrypt "$SECRETS_FILE" &>/dev/null; then
        ok "SOPS secrets decrypt correctly"
      else
        fail "SOPS failed to decrypt $SECRETS_FILE"
        echo "     Likely causes:"
        echo "     a) This host's age PUBLIC key is not in .sops.yaml"
        echo "     b) .sops.yaml doesn't have 'sops updatekeys' run after adding the key"
        echo "     Fix from another machine:"
        echo "       1. Add this host's pubkey to .sops.yaml"
        echo "       2. Run: sops updatekeys secrets/secrets.yaml"
        echo "       3. git commit && git push"
        echo "       4. git pull here and re-run this script"
        CHECKS_PASSED=false
      fi
    else
      skip "No secrets file found at $SECRETS_FILE — skipping SOPS check"
    fi

    # ── Check 4: hardware-configuration.nix ──────────────────────────────────
    green "Checking hardware-configuration.nix..."
    HW_CONF="$FLAKE_DIR/hosts/$HOSTNAME/hardware-configuration.nix"

    if [[ -f "$HW_CONF" ]]; then
      ok "hardware-configuration.nix already exists"
    else
      yellow "hardware-configuration.nix not found — generating..."
      if nixos-generate-config --show-hardware-config > "$HW_CONF" 2>/dev/null; then
        ok "Generated hardware-configuration.nix at $HW_CONF"
        yellow "IMPORTANT: Review this file before committing!"
        echo "  It may contain disk UUIDs and hardware-specific settings."
        echo "  View: cat $HW_CONF"
      else
        fail "nixos-generate-config failed"
        CHECKS_PASSED=false
      fi
    fi

    # ── Check 5: Git status summary ───────────────────────────────────────────
    green "Checking git status..."
    if [[ -d "$FLAKE_DIR/.git" ]]; then
      cd "$FLAKE_DIR"
      UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l)
      if [[ "$UNCOMMITTED" -gt 0 ]]; then
        yellow "$UNCOMMITTED uncommitted change(s) in flake repo:"
        git status --short
      else
        ok "Flake repo is clean"
      fi
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    bold "════════════════════════════════════════════════════════════════"

    if [[ "$CHECKS_PASSED" == "true" ]]; then
      bold "  ✓ All checks passed. This host is ready."
    else
      bold "  ✗ Some checks failed — see errors above before continuing."
    fi

    bold "════════════════════════════════════════════════════════════════"
    echo ""
    bold "Post-install checklist for $HOSTNAME:"
    echo ""
    echo "  Git:"
    echo "  □  Review hardware-configuration.nix:"
    echo "     cat $HW_CONF"
    echo "  □  Commit and push:"
    echo "     cd $FLAKE_DIR"
    echo "     git add hosts/$HOSTNAME/"
    echo "     git commit -m 'feat: add $HOSTNAME hardware config'"
    echo "     git push"
    echo ""
    echo "  Nightly builder (on horologium):"
    echo "  □  Add $HOSTNAME to the nightly build targets in"
    echo "     modules/nixos/optional/nix-builder.nix"
    echo "     Then: nixos-rebuild switch --flake .#horologium"
    echo ""
    echo "  Network:"
    echo "  □  Add static DHCP lease for $HOSTNAME in hosts/orion/kea.nix"
    echo "  □  Add unbound local-data entry in hosts/orion/unbound.nix"
    echo "  □  If this host needs WireGuard: add peer to hosts/lyra/default.nix"
    echo ""
    echo "  SOPS:"
    echo "  □  Verify all secrets this host needs are in secrets/secrets.yaml"
    echo "     sops secrets/secrets.yaml"
    echo ""
    echo "  Backup:"
    echo "  □  Configure restic for this host if it holds service data"
    echo ""
  '';
}


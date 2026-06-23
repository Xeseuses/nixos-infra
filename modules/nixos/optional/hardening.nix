# modules/nixos/optional/hardening.nix
#
# Lightweight security monitoring for all constellation servers.
# Enables:
#   - auditd:  kernel-level syscall/file/login auditing
#   - aide:    file integrity monitoring (daily check, alerts on unexpected changes)
#
# Import in flake.nix for: orion, eridanus, caelum, andromeda, horologium, lyra
# Skip for: vela (desktop), vanallenbelt/kepler (ISOs)
{ config, pkgs, lib, ... }:
{
  # ── auditd ────────────────────────────────────────────────────────────────
  security.auditd.enable = true;
  security.audit.enable  = true;

  security.audit.rules = [
    # ── Authentication & privilege ──────────────────────────────────────────
    "-w /etc/passwd -p wa -k identity"
    "-w /etc/group  -p wa -k identity"
    "-w /etc/shadow -p wa -k identity"
    "-w /etc/sudoers -p wa -k sudoers"
    "-w /etc/sudoers.d -p wa -k sudoers"

    # ── SSH ─────────────────────────────────────────────────────────────────
    "-w /etc/ssh/sshd_config -p wa -k sshd"
    "-w /var/lib/sops-nix -p ra -k secrets-access"

    # ── Privilege escalation ─────────────────────────────────────────────────
    "-a always,exit -F arch=b64 -S setuid -S setgid -k privilege"
    "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -k root-exec"

    # ── Nix store integrity ──────────────────────────────────────────────────
    # Alert if anything writes to the Nix store (should be immutable)
    "-w /nix/store -p wa -k nix-store-write"

    # ── Network configuration changes ────────────────────────────────────────
    "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network-change"
    "-w /etc/hosts -p wa -k network-change"

    # ── Kernel module loading ────────────────────────────────────────────────
    "-a always,exit -F arch=b64 -S init_module -S finit_module -S delete_module -k kernel-module"

    # ── Time changes ─────────────────────────────────────────────────────────
    "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change"
    "-a always,exit -F arch=b64 -S clock_settime -k time-change"

    # ── Failed file access (catches recon attempts) ───────────────────────────
    "-a always,exit -F arch=b64 -S open -S openat -F exit=-EACCES -k access-denied"
    "-a always,exit -F arch=b64 -S open -S openat -F exit=-EPERM -k access-denied"

    # Make the config immutable at runtime (prevents disabling audit mid-session)
    # Comment out if it causes issues during rebuilds:
    # "-e 2"
  ];

  # ── AIDE (file integrity monitoring) ──────────────────────────────────────
  environment.systemPackages = [ pkgs.aide ];

  # AIDE configuration — scoped to critical paths only
  # Full filesystem scan is too slow and noisy for servers with dynamic data
  environment.etc."aide.conf".text = ''
    # AIDE configuration for constellation hosts
    # Database locations
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    gzip_dbout=yes

    # Report output
    report_url=stdout
    report_url=file:/var/log/aide/aide.log

    # What to check (rule definitions)
    NORMAL = p+i+n+u+g+s+m+c+md5+sha256
    PERMS  = p+i+u+g
    LOG    = p+i+n+u+g+S

    # ── Monitored paths ──────────────────────────────────────────────────────
    # System config
    /etc   NORMAL

    # Boot
    /boot  NORMAL

    # Nix current system (changes on every rebuild — use PERMS only)
    /run/current-system PERMS

    # SOPS secrets
    /var/lib/sops-nix NORMAL

    # SSH host keys
    /etc/ssh NORMAL

    # ── Excluded paths (too dynamic to monitor usefully) ─────────────────────
    !/etc/adjtime
    !/etc/resolv.conf
    !/etc/mtab
    !/var/log
    !/var/lib/aide
    !/run
    !/proc
    !/sys
    !/dev
    !/nix/store
    !/nix/var
    !/tmp
  '';

  # Create required directories
  systemd.tmpfiles.rules = [
    "d /var/lib/aide 0700 root root -"
    "d /var/log/aide 0700 root root -"
  ];

  # ── AIDE systemd timer ─────────────────────────────────────────────────────
  # Initialize DB on first run, then check daily
  systemd.services.aide-check = {
    description = "AIDE file integrity check";
    after       = [ "network.target" ];
    serviceConfig = {
      Type            = "oneshot";
      ExecStart       = pkgs.writeShellScript "aide-check" ''
        set -euo pipefail
        DB="/var/lib/aide/aide.db"
        LOG="/var/log/aide/aide.log"
        DATE=$(date +%Y-%m-%d)

        if [ ! -f "$DB" ]; then
          echo "$DATE: Initializing AIDE database (first run)..."
          ${pkgs.aide}/bin/aide --config /etc/aide.conf --init
          mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
          echo "$DATE: AIDE database initialized" >> "$LOG"
        else
          echo "$DATE: Running AIDE integrity check..."
          # aide returns 1 if changes found, 2+ for errors
          ${pkgs.aide}/bin/aide --config /etc/aide.conf --check > /tmp/aide-report.txt 2>&1 || true

          CHANGES=$(grep -c "^[A-Z]" /tmp/aide-report.txt 2>/dev/null || echo 0)
          if [ "$CHANGES" -gt 0 ]; then
            echo "$DATE: AIDE found $CHANGES change(s):" >> "$LOG"
            cat /tmp/aide-report.txt >> "$LOG"
            echo "---" >> "$LOG"
          else
            echo "$DATE: AIDE check passed - no unexpected changes" >> "$LOG"
          fi
          rm -f /tmp/aide-report.txt
        fi
      '';
      # Run as root — needed to read all files
    };
  };

  systemd.timers.aide-check = {
    description = "Daily AIDE file integrity check";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "02:30";   # 2:30 AM daily — off-peak
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # ── Persist AIDE state ─────────────────────────────────────────────────────
  # Only add if impermanenceServer is enabled on this host
  # This is declared per-host rather than here to avoid conflicts
}


# modules/nixos/optional/hardening.nix
#
# Host-level auditd + AIDE monitoring.
# Imported on: orion, eridanus, caelum, andromeda, horologium
# NOT imported on: lyra (VPS — systemd-udevd floods audit log with EACCES,
#                   see docs Key Learnings #17), vela (not yet)
{ config, lib, pkgs, ... }:
{
  # ── auditd ──────────────────────────────────────────────────────────────
  security.auditd.enable = true;
  security.audit.enable  = true;

  security.audit.rules = [
    "-w /etc/passwd -p wa -k identity"
    "-w /etc/group -p wa -k identity"
    "-w /etc/shadow -p wa -k identity"
    "-w /etc/sudoers -p wa -k sudoers"
    "-w /etc/ssh/sshd_config -p wa -k sshd_config"
    "-w /var/lib/sops-nix -p rwa -k secrets_access"
    "-a always,exit -F arch=b64 -S setuid -S setgid -k priv_escalation"
    "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid!=0 -k root_exec"
    "-w /nix/store -p wa -k nix_store_write"
    "-a always,exit -F arch=b64 -S sethostname -k network_change"
    "-w /etc/hosts -p wa -k network_change"
    "-a always,exit -F arch=b64 -S init_module -S delete_module -k kernel_module"
    "-a always,exit -F arch=b64 -S clock_settime -k time_change"
    # NOTE: deliberately NOT watching EACCES/EPERM globally here — on VPS
    # hosts this floods the log with systemd-udevd noise. If you want
    # access-denied auditing on a specific host, scope it to a path, e.g.:
    # "-a always,exit -F arch=b64 -S open,openat -F exit=-EACCES -F dir=/etc -k access_denied"
  ];

  # ── AIDE ────────────────────────────────────────────────────────────────
  environment.systemPackages = [ pkgs.aide ];

  environment.etc."aide.conf".text = ''
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    gzip_dbout=no

    # Compound attribute groups (AIDE 0.19.x style — see `aide --version`)
    NORMAL = R
    DATAONLY = p+u+g+s+acl+selinux+xattrs+sha256

    /etc            NORMAL
    /boot           NORMAL
    /run/current-system NORMAL
    !/run/current-system/sw   # symlink target churns every rebuild, not interesting
    /var/lib/sops-nix DATAONLY
    /etc/ssh        NORMAL
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/aide 0700 root root -"
    "d /var/log/aide 0700 root root -"
  ];

  systemd.services.aide-check = {
    description = "AIDE file integrity check";
    serviceConfig.Type = "oneshot";
    script = ''
      set -uo pipefail
      DB=/var/lib/aide/aide.db
      LOG=/var/log/aide/aide.log
      REPORT=$(mktemp)

      if [ ! -f "$DB" ]; then
        echo "$(date +%F): Initializing AIDE database (first run)..." | tee -a "$LOG"
        ${pkgs.aide}/bin/aide --init --config /etc/aide.conf > "$REPORT" 2>&1
        cp /var/lib/aide/aide.db.new "$DB"
        cat "$REPORT" >> "$LOG"
      else
        ${pkgs.aide}/bin/aide --check --config /etc/aide.conf > "$REPORT" 2>&1

        # Trust AIDE's own verdict line rather than re-deriving change
        # count from grep — AIDE's summary metadata (timestamps, hashes,
        # "Number of entries") also starts with capital letters and was
        # previously miscounted as "changes" by a naive grep "^[A-Z]".
        if grep -q "found NO differences" "$REPORT"; then
          echo "$(date +%F): AIDE check passed - no unexpected changes" | tee -a "$LOG"
        else
          echo "$(date +%F): AIDE found unexpected change(s):" | tee -a "$LOG"
          cat "$REPORT" >> "$LOG"
        fi
      fi

      rm -f "$REPORT"
    '';
  };

  systemd.timers.aide-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "02:30";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
}


#!/usr/bin/env bash
# uninstall.sh — Remove 2ndBrain systemd services and credential stores.
#
# Cleans up both systemd-creds and GPG+pass credentials so the system
# can be re-deployed from scratch. Does NOT touch the vault data or
# rclone configuration.
#
# Usage:  ./scripts/uninstall.sh
set -euo pipefail

UNIT_DIR="${HOME}/.config/systemd/user"
CRED_DIR="${HOME}/.config/2ndbrain"

echo "=== 2ndBrain Uninstaller ==="
echo

# -----------------------------------------------------------------------
# 1. Stop and disable all services
# -----------------------------------------------------------------------
echo "→ Stopping and disabling services..."
for unit in brain.service rclone-2ndbrain.service rclone-2ndbrain-bisync.timer rclone-2ndbrain-bisync.service; do
    if systemctl --user is-active "${unit}" &>/dev/null; then
        systemctl --user stop "${unit}"
        echo "  Stopped ${unit}"
    fi
    if systemctl --user is-enabled "${unit}" &>/dev/null; then
        systemctl --user disable "${unit}" 2>/dev/null || true
        echo "  Disabled ${unit}"
    fi
done

# -----------------------------------------------------------------------
# 2. Remove service unit files
# -----------------------------------------------------------------------
echo "→ Removing service unit files..."
removed=0
for unit in brain.service rclone-2ndbrain.service rclone-2ndbrain-bisync.service rclone-2ndbrain-bisync.timer; do
    unit_path="${UNIT_DIR}/${unit}"
    if [[ -f "${unit_path}" ]]; then
        rm "${unit_path}"
        echo "  Removed ${unit_path}"
        removed=$((removed + 1))
    fi
done
if [[ ${removed} -eq 0 ]]; then
    echo "  (no unit files found)"
fi

systemctl --user daemon-reload

# -----------------------------------------------------------------------
# 3. Remove systemd-creds credential
# -----------------------------------------------------------------------
echo "→ Removing systemd-creds credential..."
if [[ -d "${CRED_DIR}" ]]; then
    rm -rf "${CRED_DIR}"
    echo "  Removed ${CRED_DIR}"
else
    echo "  (no systemd-creds data found)"
fi

# -----------------------------------------------------------------------
# 4. Remove GPG + pass credential
# -----------------------------------------------------------------------
echo "→ Removing GPG + pass credential..."
if command -v pass &>/dev/null && pass show rclone/gdrive-vault &>/dev/null 2>&1; then
    pass rm -f rclone/gdrive-vault
    echo "  Removed pass entry rclone/gdrive-vault"
else
    echo "  (no pass entry found)"
fi

# -----------------------------------------------------------------------
# 5. Summary
# -----------------------------------------------------------------------
echo
echo "✓ Uninstall complete."
echo
echo "  What was removed:"
echo "    • systemd user services and timers"
echo "    • systemd-creds encrypted credential (~/.config/2ndbrain/)"
echo "    • GPG pass entry (rclone/gdrive-vault)"
echo
echo "  What was NOT removed:"
echo "    • Vault data at ~/Documents/2ndBrain/"
echo "    • rclone configuration (~/.config/rclone/rclone.conf)"
echo "    • GPG keys (~/.gnupg/)"
echo "    • pass store (~/.password-store/) — only the rclone entry"
echo "    • Python venv (.venv/)"
echo "    • .env file"
echo
echo "  To re-deploy, run:"
echo "    ./scripts/install.sh --server   # or --workstation"

#!/usr/bin/env bash
# install.sh — Install 2ndBrain systemd user services.
#
# Detects whether this machine is the server (runs the brain listener)
# or a workstation (just syncs the vault for Obsidian).
#
# Credential setup is handled separately:
#   - systemd ≥ 256: run ./scripts/setup-systemd-creds.sh (rclone config password)
#                    run ./scripts/setup-env-creds.sh (.env API keys - REQUIRED)
#   - Older systemd: run ./scripts/setup-gpg-pass.sh  (manual start via ./scripts/start-brain.sh)
#                    .env credential encryption not supported - systemd ≥ 256 required
#
# DON'T install the brain.service on older systems (systemd < 256)
#
# Server mode:   rclone mount + brain.service
# Workstation:   rclone bisync on a 30s timer
#
# Usage:  ./scripts/install.sh [--server | --workstation] [--gpg]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
UNIT_DIR="${HOME}/.config/systemd/user"
ENV_FILE="${PROJECT_DIR}/.env"
MOUNT_DIR="${HOME}/Documents/2ndBrain"

# -----------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------
MODE=""
FORCE_GPG=false
for arg in "$@"; do
    case "${arg}" in
        --server)      MODE="server" ;;
        --workstation) MODE="workstation" ;;
        --gpg)         FORCE_GPG=true ;;
        *) echo "Unknown argument: ${arg}"; exit 1 ;;
    esac
done

if [[ -z "${MODE}" ]]; then
    echo "=== 2ndBrain Installer ==="
    echo
    echo "Select installation mode:"
    echo "  1) Server      — runs the Slack listener + rclone mount"
    echo "  2) Workstation — rclone bisync for Obsidian (no listener)"
    echo
    read -rp "Enter 1 or 2: " choice
    case "${choice}" in
        1) MODE="server" ;;
        2) MODE="workstation" ;;
        *) echo "Invalid choice."; exit 1 ;;
    esac
fi

echo
echo "=== 2ndBrain Installer (${MODE}) ==="
echo "Project directory: ${PROJECT_DIR}"
echo

# -----------------------------------------------------------------------
# 1. Check prerequisites
# -----------------------------------------------------------------------
REQUIRED_CMDS=(rclone)
if [[ "${MODE}" == "server" ]]; then
    REQUIRED_CMDS+=(uv python3)
fi

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is not installed. Please install it first."
        exit 1
    fi
done

# -----------------------------------------------------------------------
# 1b. Check systemd version (≥ 256 REQUIRED for server mode)
# -----------------------------------------------------------------------
SYSTEMD_VER=$(systemctl --version 2>/dev/null | head -1 | awk '{print $2}')

# Server mode requires systemd ≥ 256 for API key encryption
if [[ "${MODE}" == "server" ]]; then
    if [[ -z "${SYSTEMD_VER}" ]] || [[ "${SYSTEMD_VER}" -lt 256 ]] 2>/dev/null; then
        echo "ERROR: Server mode requires systemd ≥ 256"
        echo
        echo "  Current systemd version: ${SYSTEMD_VER:-unknown}"
        echo
        echo "  2ndBrain server requires encrypted API key storage via"
        echo "  systemd-creds, which is only available in systemd ≥ 256."
        echo
        echo "  Upgrade options:"
        echo "    - Ubuntu: Upgrade to 24.10+ (Noble has systemd 255)"
        echo "    - Fedora: Upgrade to Fedora 40+"
        echo "    - Arch: Already has systemd 257+"
        echo
        echo "  Or install as workstation mode instead (rclone sync only):"
        echo "    ./scripts/install.sh --workstation"
        exit 1
    fi
    echo "→ systemd version: ${SYSTEMD_VER} ✓"
fi

# Workstation mode can use GPG fallback for rclone config
CRED_METHOD=""
if [[ "${FORCE_GPG}" == "true" ]]; then
    if command -v pass &>/dev/null; then
        CRED_METHOD="gpg"
    else
        echo "ERROR: --gpg specified but 'pass' is not installed."
        exit 1
    fi
elif command -v systemd-creds &>/dev/null && [[ "${SYSTEMD_VER}" -ge 256 ]] 2>/dev/null; then
    CRED_METHOD="systemd-creds"
elif command -v pass &>/dev/null; then
    CRED_METHOD="gpg"
else
    echo "ERROR: No supported credential method found for rclone."
    echo
    echo "  Option 1 (systemd ≥ 256): systemd-creds is used automatically."
    echo "  Option 2 (older systemd): install 'pass' and 'gpg', then run"
    echo "           ./scripts/setup-gpg-pass.sh"
    exit 1
fi
echo "→ Rclone credential method: ${CRED_METHOD}"

# Set the password command that rclone will use
if [[ "${CRED_METHOD}" == "systemd-creds" ]]; then
    CRED_FILE="${HOME}/.config/2ndbrain/rclone-config-pass.cred"
    RCLONE_PASSWORD_CMD="systemd-creds decrypt --user --name=rclone-config-pass ${CRED_FILE} -"
else
    RCLONE_PASSWORD_CMD="pass rclone/gdrive-vault"
fi

# Check rclone remote exists.  Use --ask-password=false to avoid hanging
# when the config is encrypted and no password command is available yet.
if rclone --ask-password=false listremotes 2>/dev/null | grep -q "^gdrive-vault:"; then
    echo "→ rclone remote OK."
elif [[ "${CRED_METHOD}" == "gpg" ]] && \
     rclone listremotes --password-command "pass rclone/gdrive-vault" 2>/dev/null | grep -q "^gdrive-vault:"; then
    echo "→ rclone remote OK (via pass)."
else
    echo "⚠  Could not verify rclone remote 'gdrive-vault:'."
    echo "   If rclone.conf is encrypted, the check will pass after"
    echo "   setting up credential encryption. See docs/how-to/setup_rclone.md."
    echo
fi

# -----------------------------------------------------------------------
# 2. Python environment (server only)
# -----------------------------------------------------------------------
if [[ "${MODE}" == "server" ]]; then
    echo "→ Setting up Python virtual environment..."
    if [[ ! -d "${PROJECT_DIR}/.venv" ]]; then
        uv venv "${PROJECT_DIR}/.venv"
    fi
    cd "${PROJECT_DIR}"
    uv sync
    echo "  Done."
    echo
fi

# -----------------------------------------------------------------------
# 3. Check .env (server only)
# -----------------------------------------------------------------------
ENV_MISSING=false
if [[ "${MODE}" == "server" ]]; then
    if [[ ! -f "${ENV_FILE}" ]]; then
        echo "⚠  WARNING: No .env file found at ${ENV_FILE}"
        echo "  Copy .env.template and fill in your tokens before starting:"
        echo "    cp .env.template .env"
        echo "    \$EDITOR .env"
        echo
        ENV_MISSING=true
    else
        echo "→ .env file found."
    fi
fi

# -----------------------------------------------------------------------
# 4. Install systemd units
# -----------------------------------------------------------------------
mkdir -p "${UNIT_DIR}"

if [[ "${MODE}" == "server" ]]; then
    # --- Server: rclone mount + brain listener ---

    echo "→ Installing rclone-2ndbrain.service..."
    sed -e "s|@@RCLONE_PASSWORD_CMD@@|${RCLONE_PASSWORD_CMD}|g" \
        "${PROJECT_DIR}/service-units/rclone-2ndbrain.service" \
        > "${UNIT_DIR}/rclone-2ndbrain.service"

    echo "→ Installing brain.service..."
    sed "s|@@PROJECT_DIR@@|${PROJECT_DIR}|g" \
        "${PROJECT_DIR}/service-units/brain.service" \
        > "${UNIT_DIR}/brain.service"
    echo "  Installed (project dir: ${PROJECT_DIR})."

    # Disable workstation units if they were previously installed
    systemctl --user disable --now rclone-2ndbrain-bisync.timer 2>/dev/null || true
    systemctl --user disable rclone-2ndbrain-bisync.service 2>/dev/null || true

else
    # --- Workstation: rclone bisync on a timer ---

    echo "→ Installing rclone-2ndbrain-bisync.service..."
    sed -e "s|@@RCLONE_PASSWORD_CMD@@|${RCLONE_PASSWORD_CMD}|g" \
        "${PROJECT_DIR}/service-units/rclone-2ndbrain-bisync.service" \
        > "${UNIT_DIR}/rclone-2ndbrain-bisync.service"

    echo "→ Installing rclone-2ndbrain-bisync.timer..."
    cp "${PROJECT_DIR}/service-units/rclone-2ndbrain-bisync.timer" "${UNIT_DIR}/"

    # Disable server units if they were previously installed
    systemctl --user disable --now rclone-2ndbrain.service 2>/dev/null || true
    systemctl --user disable --now brain.service 2>/dev/null || true
fi

echo

# -----------------------------------------------------------------------
# 5. Reload and enable
# -----------------------------------------------------------------------
echo "→ Reloading systemd user daemon..."
systemctl --user daemon-reload

# -----------------------------------------------------------------------
# 6. Ensure sync directory exists
# -----------------------------------------------------------------------
mkdir -p "${MOUNT_DIR}"

# -----------------------------------------------------------------------
# 7. Start / restart
# -----------------------------------------------------------------------
if [[ "${MODE}" == "server" ]]; then
    if [[ "${ENV_MISSING}" == "true" ]]; then
        echo
        echo "⚠  Skipping service start — .env file is missing."
        echo "   After creating .env, run:"
        echo "     systemctl --user start rclone-2ndbrain.service"
        echo "     systemctl --user start brain.service"
    elif [[ "${CRED_METHOD}" == "gpg" ]]; then
        echo "→ Enabling server services (will start via ./scripts/start-brain.sh)..."
        systemctl --user enable rclone-2ndbrain.service
        systemctl --user enable brain.service
        echo
        echo "⚠  GPG credential method — services will not auto-start."
        echo "   After each reboot, run:"
        echo "     ./scripts/start-brain.sh"
    else
        # systemd-creds: check if credential file exists
        if [[ ! -f "${CRED_FILE}" ]]; then
            echo
            echo "→ Service units installed. Now run:"
            echo "    ./scripts/setup-systemd-creds.sh    # Encrypt rclone config password"
            echo "    ./scripts/setup-env-creds.sh        # Encrypt .env API keys (REQUIRED)"
            echo "  to encrypt credentials and start the services."
        else
            echo "→ Enabling and (re)starting server services..."
            systemctl --user enable rclone-2ndbrain.service
            systemctl --user enable brain.service

            echo "→ (Re)starting rclone-2ndbrain.service..."
            systemctl --user restart rclone-2ndbrain.service
            sleep 2

            echo "→ (Re)starting brain.service..."
            systemctl --user restart brain.service
            sleep 1

            echo
            echo "✓ Server services are running. Check logs with:"
            echo "    journalctl --user -u brain.service -f"
        fi
    fi
else
    # Workstation: rclone bisync on a timer

    if [[ "${CRED_METHOD}" == "gpg" ]]; then
        echo "→ Enabling bisync timer (will start via ./scripts/start-brain.sh)..."
        systemctl --user enable rclone-2ndbrain-bisync.timer
        echo
        echo "⚠  Initial vault sync: The first bisync run will download the vault"
        echo "   from Google Drive to ~/Documents/2ndBrain/2ndBrainVault/"
        echo
        echo "⚠  GPG credential method — services will not auto-start."
        echo "   After each reboot, run:"
        echo "     ./scripts/start-brain.sh"
    else
        # systemd-creds: check if credential file exists
        if [[ ! -f "${CRED_FILE:-}" ]]; then
            echo
            echo "→ Service units installed. Now run:"
            echo "    ./scripts/setup-systemd-creds.sh"
            echo "  to encrypt the rclone config password and start the timer."
            echo
            echo "  The initial sync will download the vault from Google Drive to:"
            echo "    ~/Documents/2ndBrain/2ndBrainVault/"
        else
            echo "→ Enabling and starting bisync timer..."
            systemctl --user enable rclone-2ndbrain-bisync.timer

            # Trigger the first sync manually so the user sees immediate feedback
            echo "→ Running initial bisync..."
            echo "  (The service will auto-resync if this is the first run)"
            systemctl --user start rclone-2ndbrain-bisync.service

            # Wait for the service to complete (with timeout)
            echo "  Waiting for sync to complete..."
            timeout=120
            elapsed=0
            while systemctl --user is-active --quiet rclone-2ndbrain-bisync.service; do
                sleep 2
                elapsed=$((elapsed + 2))
                if [[ $elapsed -ge $timeout ]]; then
                    echo "  ⚠  Initial sync is taking longer than expected..."
                    echo "     Check status with: journalctl --user -u rclone-2ndbrain-bisync.service -f"
                    break
                fi
            done

            # Check if it completed successfully
            if systemctl --user is-failed --quiet rclone-2ndbrain-bisync.service; then
                echo "  ⚠  Initial sync failed. Check logs:"
                echo "     journalctl --user -u rclone-2ndbrain-bisync.service --no-pager"
            elif [[ $elapsed -lt $timeout ]]; then
                echo "  ✓ Initial sync complete."
            fi

            echo "→ Starting bisync timer..."
            systemctl --user start rclone-2ndbrain-bisync.timer

            echo
            echo "✓ Bisync timer is running (every 30s). Check status with:"
            echo "    systemctl --user status rclone-2ndbrain-bisync.timer"
            echo "    systemctl --user list-timers"
            echo
            echo "  Your vault is at: ~/Documents/2ndBrain/2ndBrainVault/"
            echo "  Open it in Obsidian to start using your 2ndBrain."
        fi
    fi
fi

echo
echo "=== Installation complete ==="

#!/usr/bin/env bash
# setup-env-creds.sh — Encrypt .env API keys with systemd-creds.
#
# This script encrypts Slack and Gemini API keys from .env into individual
# systemd-creds encrypted credential files. This provides the same
# encryption-at-rest protection as the rclone config password.
#
# Requirements: systemd ≥ 256 (for `systemd-creds encrypt --user`).
# Run this AFTER install.sh has installed the service units.
#
# The encrypted credentials are stored at ~/.config/2ndbrain/*.cred — no
# plaintext files are kept on disk. At service start, systemd loads them
# via LoadCredentialEncrypted= and makes them available as files in
# $CREDENTIALS_DIRECTORY, where a wrapper script reads them into env vars.
#
# Safe to re-run — will prompt before overwriting existing credentials.
#
# Usage:  ./scripts/setup-env-creds.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR="${HOME}/.config/2ndbrain"
ENV_FILE="${PROJECT_DIR}/.env"

# Credential names — these must match LoadCredentialEncrypted in brain.service
CRED_SLACK_BOT="slack-bot-token"
CRED_SLACK_APP="slack-app-token"
CRED_GEMINI_KEY="gemini-api-key"

# -----------------------------------------------------------------------
# 1. Check prerequisites
# -----------------------------------------------------------------------
SYSTEMD_VER=$(systemctl --version 2>/dev/null | head -1 | awk '{print $2}')

if ! command -v systemd-creds &>/dev/null || [[ "${SYSTEMD_VER}" -lt 256 ]] 2>/dev/null; then
    echo "ERROR: systemd ≥ 256 is required to run 2ndBrain"
    echo
    echo "  Current systemd version: ${SYSTEMD_VER:-unknown}"
    echo
    echo "  2ndBrain requires systemd-creds for API key encryption."
    echo "  Plaintext .env files are not supported."
    echo
    echo "  Upgrade options:"
    echo "    - Ubuntu: Upgrade to 24.10+ (Noble has systemd 255)"
    echo "    - Fedora: Upgrade to Fedora 40+"
    echo "    - Arch: Already has systemd 257+"
    exit 1
fi

# -----------------------------------------------------------------------
# 2. Read secrets from .env
# -----------------------------------------------------------------------
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: No .env file found at ${ENV_FILE}"
    echo "  Create it from .env.template first:"
    echo "    cp .env.template .env"
    echo "    \$EDITOR .env"
    exit 1
fi

echo "=== systemd-creds .env Encryption Setup ==="
echo
echo "This will encrypt your API keys from .env into systemd-creds."
echo "The original .env file will NOT be deleted (you can do that manually)."
echo

# Source the .env file to read variables
# shellcheck disable=SC1090
set -a  # auto-export all variables
source "${ENV_FILE}"
set +a

# Validate required variables
MISSING_VARS=()
[[ -z "${SLACK_BOT_TOKEN:-}" ]] && MISSING_VARS+=("SLACK_BOT_TOKEN")
[[ -z "${SLACK_APP_TOKEN:-}" ]] && MISSING_VARS+=("SLACK_APP_TOKEN")
[[ -z "${GEMINI_API_KEY:-}" ]] && MISSING_VARS+=("GEMINI_API_KEY")

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    echo "ERROR: The following required variables are missing from .env:"
    printf "  - %s\n" "${MISSING_VARS[@]}"
    exit 1
fi

# -----------------------------------------------------------------------
# 3. Encrypt each credential
# -----------------------------------------------------------------------
mkdir -p "${CACHE_DIR}"

encrypt_credential() {
    local name="$1"
    local value="$2"
    local cred_file="${CACHE_DIR}/${name}.cred"

    if [[ -f "${cred_file}" ]]; then
        echo "→ ${name}.cred already exists."
        read -rp "  Overwrite? [y/N] " overwrite
        if [[ ! "${overwrite}" =~ ^[Yy] ]]; then
            echo "  Skipped."
            return
        fi
    fi

    echo "→ Encrypting ${name}..."
    echo -n "${value}" \
        | systemd-creds encrypt --user --name="${name}" - "${cred_file}"
    chmod 600 "${cred_file}"
    echo "  ✓ Saved to ${cred_file}"
}

encrypt_credential "${CRED_SLACK_BOT}" "${SLACK_BOT_TOKEN}"
encrypt_credential "${CRED_SLACK_APP}" "${SLACK_APP_TOKEN}"
encrypt_credential "${CRED_GEMINI_KEY}" "${GEMINI_API_KEY}"

# Clear sensitive variables
unset SLACK_BOT_TOKEN SLACK_APP_TOKEN GEMINI_API_KEY

# -----------------------------------------------------------------------
# 4. Verify decryption works
# -----------------------------------------------------------------------
echo
echo "→ Verifying decryption..."
ALL_OK=true

verify_credential() {
    local name="$1"
    local cred_file="${CACHE_DIR}/${name}.cred"

    if systemd-creds decrypt --user --name="${name}" "${cred_file}" - >/dev/null 2>&1; then
        echo "  ✓ ${name}"
    else
        echo "  ✗ ${name} — decryption failed!"
        ALL_OK=false
    fi
}

verify_credential "${CRED_SLACK_BOT}"
verify_credential "${CRED_SLACK_APP}"
verify_credential "${CRED_GEMINI_KEY}"

if [[ "${ALL_OK}" == "false" ]]; then
    echo
    echo "ERROR: Some credentials failed to decrypt."
    echo "  Try deleting ${CACHE_DIR}/*.cred and re-running."
    exit 1
fi

# -----------------------------------------------------------------------
# 5. Reload and restart brain.service
# -----------------------------------------------------------------------
echo
echo "→ Reloading systemd..."
systemctl --user daemon-reload

echo "→ Restarting brain.service..."
if systemctl --user is-active --quiet brain.service; then
    systemctl --user restart brain.service
    echo "  ✓ brain.service restarted."
else
    echo "  (brain.service not running — start it manually when ready)"
fi

# -----------------------------------------------------------------------
# 6. Instructions
# -----------------------------------------------------------------------
echo
echo "✓ Done. Your API keys are now encrypted at rest."
echo
echo "Encrypted credential files:"
echo "  ${CACHE_DIR}/${CRED_SLACK_BOT}.cred"
echo "  ${CACHE_DIR}/${CRED_SLACK_APP}.cred"
echo "  ${CACHE_DIR}/${CRED_GEMINI_KEY}.cred"
echo
echo "Next steps:"
echo "  1. Verify brain.service is running:"
echo "       systemctl --user status brain.service"
echo
echo "  2. (Optional) Delete the plaintext .env file:"
echo "       rm ${ENV_FILE}"
echo "       # Keep .env.template for reference"
echo
echo "  3. To decrypt a credential manually (for debugging):"
echo "       systemd-creds decrypt --user --name=${CRED_SLACK_BOT} \\"
echo "         ${CACHE_DIR}/${CRED_SLACK_BOT}.cred -"
echo

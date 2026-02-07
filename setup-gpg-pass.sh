#!/usr/bin/env bash
# setup-gpg-pass.sh — Set up GPG, pass, and keygrip preset for rclone.
#
# This script:
#   1. Creates a GPG key if none exists
#   2. Configures gpg-agent for long passphrase caching
#   3. Initialises the pass password store
#   4. Stores the rclone config password in pass
#   5. Extracts the keygrip and creates the preset script
#   6. Adds auto-preset to ~/.bashrc for headless operation
#
# Safe to re-run — skips steps that are already done.
#
# Usage:  ./setup-gpg-pass.sh
set -euo pipefail

echo "=== GPG + pass Setup for 2ndBrain ==="
echo

# -----------------------------------------------------------------------
# 1. Check prerequisites
# -----------------------------------------------------------------------
for cmd in gpg pass; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is not installed."
        echo "  sudo apt install gnupg pass   # Debian/Ubuntu"
        exit 1
    fi
done

# -----------------------------------------------------------------------
# 2. GPG key
# -----------------------------------------------------------------------
if gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -q "^sec"; then
    GPG_EMAIL=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null \
        | grep "^uid" | head -1 | sed 's/.*<\(.*\)>/\1/')
    echo "→ GPG key found: ${GPG_EMAIL}"
else
    echo "→ No GPG key found. Creating one..."
    echo "  You will be prompted for your name, email, and a passphrase."
    echo "  REMEMBER THIS PASSPHRASE — it protects your rclone config."
    echo
    gpg --full-generate-key
    GPG_EMAIL=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null \
        | grep "^uid" | head -1 | sed 's/.*<\(.*\)>/\1/')
    echo "  GPG key created for: ${GPG_EMAIL}"
fi
echo

# -----------------------------------------------------------------------
# 3. Configure gpg-agent for long caching + preset support
# -----------------------------------------------------------------------
GPG_AGENT_CONF="${HOME}/.gnupg/gpg-agent.conf"
mkdir -p "${HOME}/.gnupg"

NEEDS_UPDATE=false
for setting in "default-cache-ttl 34560000" "max-cache-ttl 34560000" "allow-preset-passphrase"; do
    if ! grep -q "^${setting%%\ *}" "${GPG_AGENT_CONF}" 2>/dev/null; then
        NEEDS_UPDATE=true
        break
    fi
done

if [[ "${NEEDS_UPDATE}" == "true" ]]; then
    echo "→ Configuring gpg-agent for long cache + preset..."
    # Remove old settings if present, then add fresh
    for key in default-cache-ttl max-cache-ttl allow-preset-passphrase; do
        sed -i "/^${key}/d" "${GPG_AGENT_CONF}" 2>/dev/null || true
    done
    cat >> "${GPG_AGENT_CONF}" << 'EOF'
default-cache-ttl 34560000
max-cache-ttl 34560000
allow-preset-passphrase
EOF
    gpgconf --kill gpg-agent
    echo "  Done. gpg-agent restarted."
else
    echo "→ gpg-agent already configured."
fi
echo

# -----------------------------------------------------------------------
# 4. Initialise pass
# -----------------------------------------------------------------------
if [[ -d "${HOME}/.password-store" ]]; then
    echo "→ pass store already initialised."
else
    echo "→ Initialising pass with GPG key: ${GPG_EMAIL}"
    pass init "${GPG_EMAIL}"
fi
echo

# -----------------------------------------------------------------------
# 5. Store rclone password in pass
# -----------------------------------------------------------------------
if pass show rclone/gdrive-vault &>/dev/null; then
    echo "→ rclone/gdrive-vault already in pass store."
else
    echo "→ Store the rclone config encryption password."
    echo "  This is the password you used (or will use) when running 'rclone config'."
    pass insert rclone/gdrive-vault
fi
echo

# -----------------------------------------------------------------------
# 6. Extract keygrip and create preset script
# -----------------------------------------------------------------------
KEYGRIP_FILE="${HOME}/.gnupg/keygrip.txt"
PRESET_SCRIPT="${HOME}/.local/bin/preset-gpg-passphrase.sh"

# Get keygrip — use the encryption subkey (ssb) if available, else primary (sec)
KEYGRIP=$(gpg --with-keygrip -K 2>/dev/null \
    | grep -A1 "ssb" | tail -1 | awk '{print $3}' || true)

if [[ -z "${KEYGRIP}" ]]; then
    # Fallback to primary key grip
    KEYGRIP=$(gpg --with-keygrip -K 2>/dev/null \
        | grep -A1 "sec" | tail -1 | awk '{print $3}' || true)
fi

if [[ -z "${KEYGRIP}" ]]; then
    echo "ERROR: Could not extract keygrip from GPG key."
    echo "  Run 'gpg --with-keygrip -K' to inspect your keys."
    exit 1
fi

echo "→ Keygrip: ${KEYGRIP}"
echo "${KEYGRIP}" > "${KEYGRIP_FILE}"
chmod 600 "${KEYGRIP_FILE}"

mkdir -p "${HOME}/.local/bin"
cat > "${PRESET_SCRIPT}" << 'SCRIPT'
#!/bin/bash
# Preset GPG passphrase into gpg-agent so pass/rclone work non-interactively.
KEYGRIP=$(cat ~/.gnupg/keygrip.txt)

# Start gpg-agent if not running
gpg-connect-agent /bye 2>/dev/null || gpg-agent --daemon 2>/dev/null

# Prompt for passphrase
read -sp "Enter GPG passphrase: " GPG_PASS
echo

# Preset it
/usr/lib/gnupg/gpg-preset-passphrase --preset "${KEYGRIP}" <<< "${GPG_PASS}"
echo "GPG passphrase cached."
SCRIPT
chmod +x "${PRESET_SCRIPT}"
echo "→ Preset script created: ${PRESET_SCRIPT}"
echo

# -----------------------------------------------------------------------
# 7. Add auto-preset to ~/.bashrc
# -----------------------------------------------------------------------
BASHRC="${HOME}/.bashrc"
MARKER="# 2ndBrain GPG auto-preset"

if grep -q "${MARKER}" "${BASHRC}" 2>/dev/null; then
    echo "→ Auto-preset already in ~/.bashrc."
else
    echo "→ Adding auto-preset to ~/.bashrc..."
    cat >> "${BASHRC}" << 'EOF'

# 2ndBrain GPG auto-preset — prompts once per login session
if [ -z "$GPG_PRESET_DONE" ]; then
    if [ -f ~/.local/bin/preset-gpg-passphrase.sh ]; then
        ~/.local/bin/preset-gpg-passphrase.sh
        export GPG_PRESET_DONE=1
    fi
fi
EOF
    echo "  Done. On next login you'll be prompted once for your GPG passphrase."
fi
echo

# -----------------------------------------------------------------------
# 8. Preset now
# -----------------------------------------------------------------------
echo "→ Presetting GPG passphrase now..."
"${PRESET_SCRIPT}"

# Verify it works
if pass show rclone/gdrive-vault &>/dev/null; then
    echo "✓ pass can decrypt rclone/gdrive-vault — setup complete!"
else
    echo "⚠ Could not decrypt rclone/gdrive-vault. Check your passphrase."
    exit 1
fi

echo
echo "=== GPG + pass setup complete ==="
echo "  You can now run ./install.sh to install the 2ndBrain services."

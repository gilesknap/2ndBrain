# Encrypt API Keys with systemd-creds

This guide shows how to encrypt your Slack and Gemini API keys using
systemd-creds. **This is required for running 2ndBrain** — plaintext
`.env` files are not supported.

## Why Mandatory Encryption?

2ndBrain requires encrypted credentials to minimize security risks.
Encrypting with systemd-creds provides defense-in-depth and **minimizes
plaintext exposure**:

| Threat | Plaintext .env | Encrypted systemd-creds |
|--------|----------------|-------------------------|
| Plaintext in environment variables | ✗ Exposed in `/proc/<pid>/environ` | ✓ **Not exposed** — decrypted in Python only |
| Malicious process as same user | ✗ Can read `.env` | ⚠ Can call `systemd-creds decrypt` |
| Accidental backup/dotfile commit | ✗ Exposed | ✓ Encrypted blob useless elsewhere |
| Stolen disk/backup drive | ✗ Exposed | ✓ Can't decrypt without host credential key |
| Memory dump of running process | ✗ In memory | ✗ In memory (unavoidable) |

**Key benefits:**
1. **No environment variable pollution** — credentials are decrypted inside
   Python code and held only in memory, not exposed via `/proc/<pid>/environ`
2. **Encryption at rest** — `.cred` files protect backups, disk images,
   and accidental exposure
3. **Minimal plaintext lifetime** — decrypted on-demand, not persisted as
   environment variables throughout the process lifetime

## Prerequisites

- **systemd ≥ 256** (check with `systemctl --version`) — **REQUIRED**
- `.env` file with your API keys (create from `.env.template`)
- `brain.service` already installed via `./scripts/install.sh`

```{warning}
systemd ≥ 256 is **required** to run 2ndBrain. If you're on older systemd,
you must upgrade before using this system.
```

## Migration Steps

### 1. Verify Your Current Setup

Check that your `.env` file has the required keys:

```bash
grep -E "^(SLACK_BOT_TOKEN|SLACK_APP_TOKEN|GEMINI_API_KEY)=" .env
```

You should see three non-empty values. If any are missing, add them first.

### 2. Run the Encryption Script

```bash
./scripts/setup-env-creds.sh
```

This will:
- Read your API keys from `.env`
- Encrypt each one into a separate `.cred` file at `~/.config/2ndbrain/`
- Verify decryption works
- Restart `brain.service` to load the encrypted credentials

**Example output:**

```
=== systemd-creds .env Encryption Setup ===

This will encrypt your API keys from .env into systemd-creds.
The original .env file will NOT be deleted (you can do that manually).

→ Encrypting slack-bot-token...
  ✓ Saved to /home/you/.config/2ndbrain/slack-bot-token.cred
→ Encrypting slack-app-token...
  ✓ Saved to /home/you/.config/2ndbrain/slack-app-token.cred
→ Encrypting gemini-api-key...
  ✓ Saved to /home/you/.config/2ndbrain/gemini-api-key.cred

→ Verifying decryption...
  ✓ slack-bot-token
  ✓ slack-app-token
  ✓ gemini-api-key

→ Reloading systemd...
→ Restarting brain.service...
  ✓ brain.service restarted.

✓ Done. Your API keys are now encrypted at rest.
```

### 3. Verify brain.service is Working

```bash
systemctl --user status brain.service
```

Check the logs to confirm it started successfully:

```bash
journalctl --user -u brain.service -n 20
```

You should see the usual startup messages (no errors about missing
environment variables).

### 4. (Optional) Delete the Plaintext .env File

Once you've confirmed everything works, you can delete `.env`:

```bash
# Make a backup first (just in case)
cp .env .env.backup

# Delete the plaintext file
rm .env

# Keep .env.template for reference
```

**Important:** After deleting `.env`, the only way to recover your keys
is via `systemd-creds decrypt`. See [](#manual-decryption)
below.

## How It Works

### Python Credential Loader

The `src.brain.credentials` module handles decryption directly in Python:

```python
from .credentials import CredentialLoader

loader = CredentialLoader()
creds = loader.load()  # Returns Credentials object

# Use credentials without exposing as environment variables
app = App(token=creds.slack_bot_token)
handler = SocketModeHandler(app, creds.slack_app_token)
```

### Decryption Flow

When the app starts (`python -m src.brain.app`):

1. **CredentialLoader.load()** checks for encrypted `.cred` files at
   `~/.config/2ndbrain/`
2. If found, it calls `systemd-creds decrypt --user` for each credential:
   ```python
   subprocess.run([
       "systemd-creds", "decrypt", "--user",
       "--name", "slack-bot-token",
       "~/.config/2ndbrain/slack-bot-token.cred", "-"
   ], capture_output=True)
   ```
3. The decrypted plaintext is captured from stdout and **held only in
   Python memory** (not written to disk or environment variables)
4. Credentials are returned as a `Credentials` dataclass and used directly
   by the app

### No Fallback to Plaintext

The credential loader **only** supports encrypted `.cred` files. If they
don't exist, the app will fail to start with a clear error message:

```python
if not self._has_systemd_creds():
    raise RuntimeError(
        "Encrypted credentials not found.\n"
        "  Run: ./scripts/setup-env-creds.sh"
    )
```

This ensures credentials are never stored in plaintext on disk.

(manual-decryption)=
## Manual Decryption

To view or retrieve a credential manually:

```bash
# Decrypt and print to stdout
systemd-creds decrypt --user \
  --name=slack-bot-token \
  ~/.config/2ndbrain/slack-bot-token.cred -

# Copy to clipboard (requires xclip or wl-clipboard)
systemd-creds decrypt --user \
  --name=gemini-api-key \
  ~/.config/2ndbrain/gemini-api-key.cred - | xclip -selection clipboard
```

## Re-encrypting or Updating Credentials

If you need to change an API key (e.g., you rotated your Slack token):

### Option 1: Re-run the Setup Script

Update `.env` with the new key, then:

```bash
./scripts/setup-env-creds.sh
```

It will prompt before overwriting existing `.cred` files.

### Option 2: Encrypt Manually

```bash
echo -n "xoxb-new-token-here" \
  | systemd-creds encrypt --user \
      --name=slack-bot-token \
      - ~/.config/2ndbrain/slack-bot-token.cred

chmod 600 ~/.config/2ndbrain/slack-bot-token.cred

systemctl --user restart brain.service
```

## Troubleshooting

### Service fails to start with "credential not found"

**Symptom:**

```
journalctl --user -u brain.service
...
ERROR: One or more required credentials are missing from /run/user/.../credentials/...
```

**Cause:** The `.cred` file doesn't exist or systemd couldn't decrypt it.

**Fix:**

1. Check the files exist:
   ```bash
   ls -lh ~/.config/2ndbrain/*.cred
   ```

2. Test decryption manually:
   ```bash
   systemd-creds decrypt --user \
     --name=slack-bot-token \
     ~/.config/2ndbrain/slack-bot-token.cred -
   ```

3. If decryption fails, re-run `./scripts/setup-env-creds.sh`

### "systemd-creds: command not found" when running

**Symptom:** Application fails with subprocess error about systemd-creds.

**Cause:** The Python code calls `systemd-creds decrypt` but the command
isn't available (systemd < 256).

**Fix:** Upgrade systemd to ≥ 256:

```bash
# Check current version
systemctl --version

# Ubuntu/Debian: Upgrade systemd (may require newer OS version)
sudo apt update
sudo apt install systemd

# Verify version
systemctl --version  # Must show ≥ 256
```

**There is no plaintext .env fallback** — systemd ≥ 256 is mandatory.

### Credential files exist but service still fails

**Symptom:** The `.cred` files are present, but the service won't start.

**Cause:** systemd might not have permission to read them, or the
credential key has changed (e.g., after a system reinstall).

**Fix:**

1. Check file permissions:
   ```bash
   chmod 600 ~/.config/2ndbrain/*.cred
   ```

2. Re-encrypt from `.env`:
   ```bash
   rm ~/.config/2ndbrain/*.cred
   ./scripts/setup-env-creds.sh
   ```

### How to view encrypted credentials

To view your credentials without starting the app:

```bash
# View a single credential
systemd-creds decrypt --user \
  --name=slack-bot-token \
  ~/.config/2ndbrain/slack-bot-token.cred -

# Export credentials temporarily (for debugging)
export SLACK_BOT_TOKEN=$(systemd-creds decrypt --user --name=slack-bot-token ~/.config/2ndbrain/slack-bot-token.cred -)
export SLACK_APP_TOKEN=$(systemd-creds decrypt --user --name=slack-app-token ~/.config/2ndbrain/slack-app-token.cred -)
export GEMINI_API_KEY=$(systemd-creds decrypt --user --name=gemini-api-key ~/.config/2ndbrain/gemini-api-key.cred -)
```

**Note:** There is no way to run 2ndBrain without encrypted credentials.

## Security Considerations

### What This Does

- **Encrypts secrets at rest** — `.cred` files are useless on a different
  machine or if the credential key is unavailable
- **Protects backups** — If you back up `~/.config/2ndbrain/`, the
  encrypted blobs don't leak your keys
- **Prevents accidental commits** — A `.cred` file committed to git is not
  exploitable
- **Minimizes plaintext exposure** — Credentials are decrypted on-demand
  in Python code, NOT exposed as environment variables in `/proc/<pid>/environ`

### What This Does NOT Do

- **Does NOT protect against a compromised user session** — If an attacker
  has your UID and can run `systemd-creds decrypt`, they can retrieve the
  keys (but they'd need to know to look for them, unlike environment variables)
- **Does NOT prevent runtime memory access** — Credentials exist in Python
  process memory while the app is running (unavoidable for any application
  that needs to use them)
- **Does NOT require a passphrase** — The decryption is automatic (no
  manual unlock like GPG). This is by design for auto-start on boot.

### Comparison to rclone Config Encryption

| Aspect | rclone config | .env keys (this guide) |
|--------|---------------|------------------------|
| Encryption at rest | ✓ | ✓ |
| Auto-decrypt on boot | ✓ (systemd-creds) | ✓ (systemd-creds) |
| Requires passphrase | No (systemd-creds) or Yes (GPG) | No (systemd-creds only) |
| Rotation ease | Moderate (OAuth flow) | Minutes (copy new key) |

The main difference is that **Slack/Gemini keys are trivially rotated**,
so the cost of a compromise is lower than the rclone OAuth token.

## Advanced: Using GPG Instead

If you prefer a passphrase-protected approach like the rclone GPG setup,
you can store `.env` keys in `pass`:

```bash
# Store each key in pass
pass insert 2ndbrain/slack-bot-token
pass insert 2ndbrain/slack-app-token
pass insert 2ndbrain/gemini-api-key

# Update load-creds-and-run.sh to call `pass` instead of reading
# from $CREDENTIALS_DIRECTORY
```

This is **not recommended** because:
- Adds complexity (GPG agent, manual unlock)
- Doesn't integrate with systemd's credential system
- Slack/Gemini keys don't warrant the same protection as the rclone token

## Next Steps

- Return to the [Quick Start](../tutorials/quickstart.md) to continue setup
- See [Security](../explanations/security.md) for the full threat model
- Check the [Decision Record](../explanations/decisions/0003-secret-storage-and-account-separation.md)
  for why this approach was chosen

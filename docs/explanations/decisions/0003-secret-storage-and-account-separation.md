# 3. Secret Storage and Account Separation

## Status

Accepted

## Context

The 2ndBrain server runs on a LAN with no external exposure. It handles
three categories of secret:

| Secret                  | Scope                          | Rotation ease |
|-------------------------|--------------------------------|---------------|
| Slack bot/app tokens    | Slack workspace only           | Minutes       |
| Gemini API key          | Gemini API only                | Minutes       |
| rclone OAuth2 refresh token | Google Drive (scoped to one folder) | Moderate |

The existing setup uses GPG + `pass` to encrypt the rclone config, and
a plaintext `.env` (mode 600) for Slack/Gemini keys. We considered three
alternatives:

1. **Move all secrets into GPG/pass** — encrypt `.env` values alongside
   the rclone config.
2. **Run rclone and brain as separate OS users** — isolate the OAuth
   token behind a user boundary so prompt injection in the brain service
   can't reach it.
3. **Keep current approach** — GPG-encrypted rclone config, plaintext
   `.env` with file permissions.

## Decision

Keep the current approach (option 3). Do not add GPG for Slack/Gemini
keys, and do not introduce user separation.

### Rationale

**Against GPG for all secrets:**
- If an attacker has read access to `~/.env` (mode 600), they almost
  certainly also have access to the running GPG agent and can call `pass`
  directly. The encryption adds complexity without meaningful protection.
- systemd's `EnvironmentFile=` can't read from `pass` — would need a
  wrapper script, adding a failure mode.
- Slack/Gemini keys are trivially rotated if compromised.

**Against user separation:**
- The primary prompt-injection threat is exfiltration or corruption of
  vault data. The brain service already has full write access to the
  vault via the FUSE mount — user separation wouldn't protect the data
  itself.
- The rclone remote is scoped to a single Drive folder containing only
  vault data, not the whole Drive. The OAuth token grants access to the
  same data the attacker can already reach through the mount.
- Adds systemd wiring complexity (`User=` directives, `--allow-other`
  FUSE config, group permissions on mount point).

**Keeping rclone config encryption (status quo):**
- It's already working and is a built-in rclone feature, not custom
  infrastructure.
- Provides defence-in-depth against accidental exposure (backups,
  dotfile commits) even if it doesn't help against a compromised user
  session.

## Consequences

- The main attack surface for prompt injection remains input
  sanitisation: slug/path validation in `vault.py` and ensuring Gemini
  output is never passed to `eval()` or a shell.
- If the rclone remote scope is ever broadened beyond the vault folder,
  this decision should be revisited — a full-Drive token behind only
  file permissions would be a different risk profile.
- New machines can optionally skip rclone config encryption and rely on
  `chmod 600` alone if the GPG setup is too burdensome.

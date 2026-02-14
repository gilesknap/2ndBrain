"""
credentials.py — Secure credential loading with systemd-creds.

This module loads API credentials from systemd-creds encrypted files.
Credentials are decrypted on-demand and held only in memory (not exposed
as environment variables). The encrypted .cred files are read and decrypted
by calling systemd-creds directly.

This approach provides:
- Encryption at rest (credentials never stored in plaintext on disk)
- Minimal plaintext exposure (decrypted only when needed, held in memory)
- No environment variable pollution (/proc/<pid>/environ stays clean)

Requires systemd ≥ 256 for systemd-creds support.
"""

import logging
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Credentials:
    """Container for API credentials."""

    slack_bot_token: str
    slack_app_token: str
    gemini_api_key: str


class CredentialLoader:
    """
    Load credentials from systemd-creds encrypted files.

    Usage:
        loader = CredentialLoader()
        creds = loader.load()
        app = App(token=creds.slack_bot_token)
    """

    def __init__(self, cred_dir: Path | None = None):
        """
        Initialize the credential loader.

        Args:
            cred_dir: Directory containing .cred files (default: ~/.config/2ndbrain)
        """
        self.cred_dir = cred_dir or Path.home() / ".config" / "2ndbrain"
        self.logger = logging.getLogger(__name__)

    def load(self) -> Credentials:
        """
        Load credentials from systemd-creds encrypted files.

        Returns:
            Credentials object with all required API keys.

        Raises:
            RuntimeError: If credentials cannot be loaded or are incomplete.
        """
        if not self._has_systemd_creds():
            raise RuntimeError(
                "Encrypted credentials not found.\n"
                "  Run: ./scripts/setup-env-creds.sh\n"
                f"  Expected files:\n"
                f"    {self.cred_dir}/slack-bot-token.cred\n"
                f"    {self.cred_dir}/slack-app-token.cred\n"
                f"    {self.cred_dir}/gemini-api-key.cred"
            )

        self.logger.info("Loading credentials from systemd-creds")
        return self._load_from_systemd_creds()

    def _has_systemd_creds(self) -> bool:
        """Check if systemd-creds encrypted files exist."""
        required_creds = [
            self.cred_dir / "slack-bot-token.cred",
            self.cred_dir / "slack-app-token.cred",
            self.cred_dir / "gemini-api-key.cred",
        ]
        return all(p.exists() for p in required_creds)

    def _load_from_systemd_creds(self) -> Credentials:
        """
        Decrypt and load credentials from systemd-creds.

        This calls `systemd-creds decrypt --user` for each credential,
        reading the plaintext output directly into memory.
        """
        try:
            slack_bot = self._decrypt_credential("slack-bot-token")
            slack_app = self._decrypt_credential("slack-app-token")
            gemini_key = self._decrypt_credential("gemini-api-key")

            return Credentials(
                slack_bot_token=slack_bot,
                slack_app_token=slack_app,
                gemini_api_key=gemini_key,
            )
        except subprocess.CalledProcessError as e:
            raise RuntimeError(
                f"Failed to decrypt credential: {e}\n"
                "  Try running: ./scripts/setup-env-creds.sh"
            ) from e

    def _decrypt_credential(self, name: str) -> str:
        """
        Decrypt a single systemd-creds credential.

        Args:
            name: Credential name (e.g., "slack-bot-token")

        Returns:
            Decrypted credential value (plaintext string).

        Raises:
            subprocess.CalledProcessError: If decryption fails.
            RuntimeError: If systemd-creds is not available.
        """
        cred_file = self.cred_dir / f"{name}.cred"

        try:
            result = subprocess.run(
                [
                    "systemd-creds",
                    "decrypt",
                    "--user",
                    "--name",
                    name,
                    str(cred_file),
                    "-",  # Output to stdout
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        except FileNotFoundError:
            raise RuntimeError(
                "systemd-creds command not found.\n"
                "  This requires systemd ≥ 256.\n"
                "  Check your systemd version: systemctl --version"
            ) from None

        credential = result.stdout.strip()

        if not credential:
            raise RuntimeError(f"Decrypted credential '{name}' is empty")

        return credential

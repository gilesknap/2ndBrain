#!/usr/bin/env python3
"""
app.py — Application entrypoint.

Sets up logging, validates environment, initialises all components,
and starts the Slack socket-mode listener with the daily briefing
scheduler running in a background thread.
"""

import logging
import os
import sys

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

from .agents import Router
from .agents.filing import FilingAgent
from .agents.memory import MemoryAgent
from .agents.vault_edit import VaultEditAgent
from .agents.vault_query import VaultQueryAgent
from .briefing import start_scheduler
from .credentials import CredentialLoader
from .listener import register_listeners
from .vault import Vault

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    # Load credentials (systemd-creds encrypted files required)
    try:
        loader = CredentialLoader()
        creds = loader.load()
    except RuntimeError as e:
        logging.critical(str(e))
        sys.exit(1)

    # Store Gemini API key in environment for google-genai SDK
    # (The SDK expects GEMINI_API_KEY in os.environ)
    os.environ["GEMINI_API_KEY"] = creds.gemini_api_key

    # Initialise Vault (creates folders + .base files on first run)
    vault = Vault()

    # Initialise pluggable agents
    filing_agent = FilingAgent(existing_projects=vault.list_projects())
    vault_query_agent = VaultQueryAgent()
    vault_edit_agent = VaultEditAgent()
    memory_agent = MemoryAgent()

    # Build the router with registered agents
    router = Router(
        agents={
            filing_agent.name: filing_agent,
            vault_query_agent.name: vault_query_agent,
            vault_edit_agent.name: vault_edit_agent,
            memory_agent.name: memory_agent,
        },
        default_agent="file",
    )

    # Initialise Slack app with credentials from secure loader
    app = App(token=creds.slack_bot_token)

    # Wire up event handlers
    register_listeners(app, vault, router)

    # Start daily briefing scheduler in background thread
    start_scheduler(app.client, vault)

    # Start listening
    logging.info("⚡️ 2ndBrain Collector starting up...")
    handler = SocketModeHandler(app, creds.slack_app_token)
    handler.start()


if __name__ == "__main__":
    main()

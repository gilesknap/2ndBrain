#!/usr/bin/python3
import json
import logging
import os
import re
from datetime import datetime
from pathlib import Path

import google.generativeai as genai
from dotenv import load_dotenv
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

# 1. Setup & Configuration
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
load_dotenv()
BASE_VAULT_PATH = Path.home() / "Documents" / "2ndBrain"
# Ensure our core directories exist
for folder in ["Inbox", "Projects", "Actions", "Ideas", "Media"]:
    (BASE_VAULT_PATH / folder).mkdir(parents=True, exist_ok=True)

# Initialize AI
genai.configure(api_key=os.environ.get("GEMINI_API_KEY"))
app = App(token=os.environ.get("SLACK_BOT_TOKEN"))


def process_with_gemini(raw_text):
    """
    Categorizes the note into folders and cleans up the Markdown content.
    """
    model = genai.GenerativeModel("gemini-2.5-flash")

    # Prompt reflects the logic defined in your AGENTS.md
    prompt_file = Path(__file__).parent / "slack_prompt.md"
    prompt = prompt_file.read_text() + f"\n\nInput:\n{raw_text}"

    response = model.generate_content(prompt)

    # Extract Token Usage for your frontmatter
    usage = response.usage_metadata
    tokens = usage.total_token_count

    # Extract JSON string from response
    json_match = re.search(r"\{.*\}", response.text, re.DOTALL)
    if not json_match:
        # assume this is an unstructured answer to a question
        return response.text, tokens, True

    data = json.loads(json_match.group())

    data["content"] = data["content"].replace("tags:", f"tokens_used: {tokens}\ntags:")

    return data, tokens, False


@app.event("message")
def handle_message(event, say):
    # Ignore bot messages and channel joins/leaves
    if event.get("subtype") or event.get("bot_id"):
        return

    text = event.get("text")
    logging.info(f"📥 Incoming from Slack: {text[:50]}...")

    try:
        # The AI "Refiner" Step
        data, token_count, is_answer = process_with_gemini(text)

        if is_answer:
            say(data)
            return

        # Determine final file path
        target_folder = BASE_VAULT_PATH / data["folder"]
        file_path = target_folder / data["filename"]

        # Write the file
        with open(file_path, "w") as f:
            f.write(data["content"])

        # Logging to journalctl
        logging.info(
            f"Filed to {data['folder']}/{data['filename']} ({token_count} tokens)"
        )

        # Feedback to user in Slack
        say(
            f"📂 Filed to `{data['folder']}` as `{data['filename']}`. (Used {token_count} tokens)"
        )

    except Exception as e:
        logging.exception("Error processing message")
        say(f"⚠️ Brain Error: {str(e)}")


if __name__ == "__main__":
    logging.info("⚡️ 2ndBrain Collector is starting up...")
    handler = SocketModeHandler(app, os.environ.get("SLACK_APP_TOKEN"))
    handler.start()

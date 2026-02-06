#!/usr/bin/python3
import os
import re
import json
from datetime import datetime
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler
import google.generativeai as genai
from dotenv import load_dotenv

# 1. Setup & Environment
load_dotenv()
VAULT_PATH = os.path.expanduser("~/Documents/2ndBrain/Inbox")
os.makedirs(VAULT_PATH, exist_ok=True)

genai.configure(api_key=os.environ.get("GEMINI_API_KEY"))
app = App(token=os.environ.get("SLACK_BOT_TOKEN"))

def process_with_gemini(raw_text):
    # Using the 2026 stable workhorse model
    model = genai.GenerativeModel('gemini-2.5-flash')

    prompt = f"""
    System: Expert Knowledge Management Assistant for an Obsidian Vault.
    Task: Convert the Slack message into a structured Markdown note.

    Instructions:
    - Generate a slugified filename: 'capture-YYYYMMDD-HHmm.md'.
    - Create a YAML frontmatter with: date, source: slack, and tags.
    - Sanitize Slack's link format <URL|NAME> into [NAME](URL).
    - If it's a list or task, use proper Markdown syntax.

    Input Message: "{raw_text}"

    Response Format: Return ONLY a raw JSON object with keys "filename" and "content".
    """

    response = model.generate_content(prompt)

    # Token Tracking
    usage = response.usage_metadata
    tokens = usage.total_token_count

    # Extract JSON from potential markdown blocks
    json_str = re.search(r'\{.*\}', response.text, re.DOTALL).group()
    data = json.loads(json_str)

    # Inject token usage into the Markdown content's frontmatter
    data['content'] = data['content'].replace(
        "tags:", f"tokens_used: {tokens}\ntags:"
    )

    return data, tokens

@app.event("message")
def handle_message(event, say):
    # Filter out bots and subtypes (joins/leaves)
    if event.get("subtype") or event.get("bot_id"):
        return

    text = event.get("text")
    user_id = event.get("user")

    try:
        data, token_count = process_with_gemini(text)
        file_path = os.path.join(VAULT_PATH, data['filename'])

        with open(file_path, "w") as f:
            f.write(data['content'])

        print(f"[{datetime.now()}] Filed: {data['filename']} | Tokens: {token_count}")
        say(f"✅ Filed as `{data['filename']}`. Usage: {token_count} tokens.")

    except Exception as e:
        print(f"Error processing message: {e}")
        say(f"⚠️ Error: Failed to process that note.")

if __name__ == "__main__":
    handler = SocketModeHandler(app, os.environ.get("SLACK_APP_TOKEN"))
    handler.start()
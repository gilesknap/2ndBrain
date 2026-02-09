# Slack App Setup

This guide walks through creating the Slack app used by the 2ndBrain
Collector. The app listens for direct messages via Socket Mode and needs
specific OAuth scopes to read messages, download files, and reply.

## 1. Create the App

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and click
   **Create New App**.
2. Choose **From scratch**.
3. Name it (e.g. `2ndBrain_Collector`) and select your workspace.
4. Click **Create App**.

## 2. Enable Socket Mode

Socket Mode lets the app receive events over a WebSocket instead of
requiring a public HTTP endpoint.

1. In the left sidebar, go to **Settings → Socket Mode**.
2. Toggle **Enable Socket Mode** on.
3. You'll be prompted to create an **App-Level Token**. Give it a name
   (e.g. `brain-socket`) and add the scope `connections:write`.
4. Click **Generate**. Copy the token — it starts with `xapp-`. This is
   your `SLACK_APP_TOKEN`.

## 3. Subscribe to Events

1. Go to **Features → Event Subscriptions**.
2. Toggle **Enable Events** on.
3. Under **Subscribe to bot events**, add:
   - `message.im` — triggers when someone sends a direct message to the bot
4. Click **Save Changes**.

## 4. Configure Bot Token Scopes

1. Go to **Features → OAuth & Permissions**.
2. Scroll to **Scopes → Bot Token Scopes**.
3. Add the following scopes:

| Scope                | Purpose                                              |
|----------------------|------------------------------------------------------|
| `app_mentions:read`  | View messages that directly mention @2ndBrain        |
| `channels:history`   | View messages in public channels the app is in       |
| `chat:write`         | Send messages as @2ndBrain                           |
| `files:read`         | Download file attachments shared in conversations    |
| `groups:history`     | View messages in private channels the app is in      |
| `im:history`         | View messages in direct messages with the bot        |
| `incoming-webhook`   | Post messages to specific channels (for briefings)   |

4. Click **Save Changes** if prompted.

## 5. Install the App to Your Workspace

1. Scroll to the top of the **OAuth & Permissions** page.
2. Click **Install to Workspace** (or **Reinstall to Workspace** if
   updating scopes).
3. Review the permissions and click **Allow**.
4. Copy the **Bot User OAuth Token** — it starts with `xoxb-`. This is
   your `SLACK_BOT_TOKEN`.

> **Important:** You must reinstall the app to your workspace every time
> you add or change scopes. The new permissions don't take effect until
> you do.

## 6. Configure Environment Variables

Add both tokens plus your Gemini API key to the `.env` file at the project
root (`~/2nd_brain/.env`):

```bash
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_APP_TOKEN=xapp-your-app-level-token
GEMINI_API_KEY=your-gemini-api-key

# Optional — daily briefing
# BRIEFING_CHANNEL=C0123456789
# BRIEFING_TIME=07:00
```

See `.env.template` for a reference.

## 7. Find the Briefing Channel ID (Optional)

If you want the daily briefing feature, you need the Slack channel ID:

1. Open Slack and navigate to the channel.
2. Click the channel name at the top to open details.
3. Scroll to the bottom — the Channel ID is shown there (e.g.
   `C0123456789`).
4. Set `BRIEFING_CHANNEL=C0123456789` in your `.env`.
5. Make sure the bot has been **added to that channel** (invite it with
   `/invite @2ndBrain_Collector`).

## 8. Test the Connection

Start the service and check the logs:

```bash
cd ~/2nd_brain
./scripts/restart.sh
# or manually:
systemctl --user restart brain.service
journalctl --user -u brain.service -f
```

You should see:
```
⚡️ 2ndBrain Collector starting up...
A new session has been established (session id: ...)
⚡️ Bolt app is running!
```

Send a DM to @2ndBrain in Slack — it should respond with a confirmation
and file the note into the vault.

## Troubleshooting

| Problem                          | Fix                                            |
|----------------------------------|-------------------------------------------------|
| `invalid_auth` error             | Check `SLACK_BOT_TOKEN` is correct and current |
| Files download as HTML           | Ensure `files:read` scope is added and app is reinstalled |
| Bot doesn't respond to DMs       | Check `message.im` event subscription is enabled |
| `missing_scope` error            | Add the missing scope and reinstall the app    |
| Socket mode connection fails     | Check `SLACK_APP_TOKEN` (xapp-) and that Socket Mode is enabled |

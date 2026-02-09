# Obsidian Setup

This guide covers installing and configuring Obsidian to work with your
2ndBrain vault.

## Installation

### Desktop (Windows, macOS, Linux)

1. Download from [obsidian.md](https://obsidian.md/)
2. Install and launch
3. Skip the onboarding prompts

### Mobile (iOS/Android)

1. Install from App Store or Google Play
2. Purchase Obsidian Sync or use a third-party sync solution
   (Obsidian Sync is not required if you're using rclone bisync on a desktop)

## Opening Your Vault

Once your vault has been synced to this machine:

1. Launch Obsidian
2. Click **Open folder as vault**
3. Navigate to and select `~/Documents/2ndBrain/2ndBrainVault/`
4. Obsidian will index the vault and show the file tree

Changes you make in Obsidian will automatically sync back to Google Drive
within 30 seconds (via rclone bisync on the local machine, or the rclone
mount on a server).

## Recommended Plugins

### Metadata Menu

The Metadata Menu plugin adds a UI for editing YAML frontmatter, making it
easier to modify note properties without manual editing.

#### Installation

1. In Obsidian, go to **Settings** → **Community plugins**
2. Disable "Restricted mode" if prompted
3. Click **Browse** and search for "Metadata Menu"
4. Click **Install**, then **Enable**

The plugin ships with a pre-configured template in `.obsidian/plugins/metadata-menu/data.json`
that defines property types and validation for your vault structure. This
file is synced from the 2ndBrain project templates automatically.

### Optional Plugins

Consider these for enhanced functionality:

- **Calendar** — Quick date navigation
- **Quick Capture** — Keyboard shortcut to add notes
- **Tasks** — Render todo items with due dates from frontmatter
- **Recent Files** — Quick access sidebar

## CSS Snippets

The vault includes a custom CSS snippet (`base-width.css`) that optimizes
the appearance of Obsidian Bases and dashboards.

### Enable the CSS Snippet

1. In Obsidian, go to **Settings** → **Appearance**
2. Scroll to **CSS snippets**
3. Click the folder icon to open the snippets folder
4. The `base-width.css` file should appear in the list
5. Toggle it on (enable it)

The snippet adjusts the maximum width of base views for better readability.

## Using Dashboards and Bases

The vault includes several `.base` files that provide filtered views of your
notes:

| File                    | Purpose                                   |
|-------------------------|-------------------------------------------|
| `_brain/Dashboard.base` | Master dashboard with today's actions     |
| `_brain/Actions.base`  | All actions grouped by status              |
| `_brain/Media.base`      | Media items grouped by type                |
| `_brain/Projects.base`| All projects with priority sorting         |
| `_brain/Reference.base` | Reference notes grouped by topic         |
| `_brain/Memories.base`| Personal memories and experiences         |

These files use Obsidian's native **Base** feature (not a plugin) to create
filtered, sortable, grouped views. Open any `.base` file to see how your
notes are organized.

```{note}
Bases require Obsidian version 1.4 or later. If you see a "Base not found"
error, upgrade Obsidian: **Settings** → **About** → **Check for updates**.
```

## Syncing with 2ndBrain Agents

The vault automatically receives notes filed by the bot via Slack. You can
influence how notes are organized by:

1. **Adding directives** — In Slack, message the bot:
   ```
   remember: always tag photography with #photography
   ```

2. **Using project hashtags** — In your Slack message:
   ```
   This is a great coffee recipe #projects/coffee-experiments
   ```
   The bot will associate the note with that project folder.

3. **Using directives** — Teach the bot classification rules with
   persistent directives:
   ```
   remember: always tag coffee recipes with #coffee #recipes
   remember: coffee content goes to Projects/Coffee Experiments
   ```
   Directives are stored in the vault and influence all future filings.

## Working Offline

If rclone bisync isn't running (e.g., laptop offline), you can still edit
notes locally. When sync resumes:

- **Local changes** are uploaded to Google Drive
- **Changes from other machines** are downloaded and merged
- Conflicts are resolved using **`--conflict-resolve newer`** (latest
  timestamp wins)

For best results during extended offline use, commit your changes to Git
(if using Git on your local vault):

```bash
cd ~/Documents/2ndBrain/2ndBrainVault
git add -A
git commit -m "Offline edits"
```

## Troubleshooting

### Vault Not Syncing

1. Check that rclone bisync is running:
   ```bash
   systemctl --user status rclone-2ndbrain-bisync.timer
   ```

2. Check the sync logs:
   ```bash
   journalctl --user -u rclone-2ndbrain-bisync.service -f
   ```

3. Verify the vault folder exists:
   ```bash
   ls ~/Documents/2ndBrain/2ndBrainVault/
   ```

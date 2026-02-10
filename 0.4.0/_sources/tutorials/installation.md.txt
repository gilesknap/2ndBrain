# Installation

## Prerequisites

- Python 3.12 or later
- [uv](https://docs.astral.sh/uv/) package manager
- **rclone 1.58.0 or later** (workstation mode requires `bisync`)
- A configured Slack app (see [Slack App Setup](../how-to/setup_slack_app.md))
- rclone configured for Google Drive (see [rclone Setup](../how-to/setup_rclone.md))

## Clone and install

```bash
$ git clone https://github.com/gilesknap/2ndBrain.git
$ cd 2ndBrain
$ uv sync
```

## Verify the installation

```bash
$ uv run brain --version
```

## Deployment

Use the included installer for either server or workstation mode:

```bash
$ ./scripts/install.sh --server       # Headless: rclone FUSE mount + Slack listener
$ ./scripts/install.sh --workstation  # Desktop:  rclone bisync for Obsidian
```

### Workstation Initial Sync

When installing in workstation mode for the first time, the vault will be
synced from Google Drive automatically:

- The bisync service checks for existing sync state on every run
- If no state exists, it performs an initial `--resync` to establish
  the baseline before the regular sync
- Your vault appears at `~/Documents/2ndBrain/2ndBrainVault/`

For GPG credential mode, the sync happens when you first run
`./scripts/start-brain.sh` after installation.

See the [Quick Start](quickstart.md) for the full deployment
workflow including credential setup.

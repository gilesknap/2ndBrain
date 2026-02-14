# Using Zed with Claude Code

I'm trying using zed for the first time on this project and am experimenting with Claude Code agent integration. (also github copilot)

## Installation

### Zed Editor

1. Download from [zed.dev](https://zed.dev/)
2. Install for your platform (macOS, Linux, or Windows)
3. Launch Zed

### Claude Code Extension

1. Open Zed's extensions panel (**⌘+,** on macOS or **Ctrl+,** on Linux/Windows)
2. Search for "Claude Code"
3. Click **Install**
4. Restart Zed to activate the extension

## Dev Container

I'm not sure that Github Copilot works in devcontainers.

To make the devcontainer work with Claude Code extension, add this to the `.devcontainer/devcontainer.json` file:

```json

    // make sure the claude folder is created for claude in devcontainer auth
    "initializeCommand": "mkdir -p ${localEnv:HOME}/.config/terminal-config ${localEnv:HOME}/.claude",
    "mounts": [
      // mount the claude folder for claude in devcontainer auth
      {
        "source": "${localEnv:HOME}/.claude",
            "target": "/root/.claude",
            "type": "bind"
        }
    ],
```

This brings in the auth tokens from the external claude code. Make sure you log in outside first, as inside requires nodejs and the oauth flow is fiddly.

The following `.zed/settings.json` configuration was required to get venv working inside a dev container:

```{literalinclude} ../../.zed/settings.json
:language: json
```

## Still Broken Anyway

But still other stuff fails like git config etc. Because its not running the correct shell:

I get the same behavior using the devcontainer cli like this:

```bash
devcontainer up --docker-path podman
podman exec container_name bash
```

Whereas using the devcontainer cli like the following works:

```bash
devcontainer up --docker-path podman
devcontainer exec --docker-path podman bash
```

Perhaps zed is execing bash instead of getting a shell with the devcontainer cli?

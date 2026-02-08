# Rclone Setup

```{note}
Most of this guide is automated by `./install.sh`. The script checks for
rclone, sets file permissions, and installs the systemd services. Read on
if you need to understand the individual steps or troubleshoot.
```

This guide provides a secure, portable method for mounting a specific Google Drive folder to a local Linux directory (`~/Documents/2ndBrain`).

## 1. Prerequisites

Install the required system tools:

```bash
# Ubuntu/Debian/Mint
sudo apt install rclone fuse3

# RHEL/Fedora/CentOS
sudo yum install rclone fuse3
```

---

## 2. Configuration Strategy

To ensure the mount is both secure and portable, we use two key principles:

1. **Root Isolation:** Use the `root_folder_id` in the config to lock access to a single folder.
2. **File Permissions:** The `rclone.conf` file is protected with mode 600 (owner read/write only).

---

## 3. Security: File Permissions

The rclone configuration file at `~/.config/rclone/rclone.conf` contains
your Google Drive OAuth tokens. It is protected by file permissions — the
installer enforces mode 600 so only your user can read it.

This is sufficient for a personal automation tool: if someone has access
to your user account, they already have access to everything else. No
additional encryption layer (GPG, pass, etc.) is needed.

```bash
# The installer does this automatically, but you can verify:
chmod 600 ~/.config/rclone/rclone.conf
ls -l ~/.config/rclone/rclone.conf
# Should show: -rw------- 1 youruser youruser ...
```

---

## 4. Systemd Service

The service files are installed automatically by `./install.sh`. They use
specifiers (`%h`) to work on any machine regardless of username.

The key service file is `rclone-2ndbrain.service`:

```ini
[Unit]
Description=RClone Mount for 2ndBrain
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount gdrive-vault: %h/Documents/2ndBrain \
  --vfs-cache-mode full \
  --vfs-cache-max-age 24h \
  --vfs-cache-max-size 10G
ExecStop=/usr/bin/fusermount -u %h/Documents/2ndBrain
Restart=on-failure

[Install]
WantedBy=default.target
```

---

## 5. Deployment & Maintenance

### Launching the System

```bash
# Create the mount point directory
mkdir -p ~/Documents/2ndBrain

# Enable lingering to allow service to run on boot without login
sudo loginctl enable-linger $USER

# Reload systemd and start the service
systemctl --user daemon-reload
systemctl --user enable --now rclone-2ndbrain.service

# Check the status
systemctl --user status rclone-2ndbrain.service
```

### The "Nuclear" Reset (For 'Directory Busy' errors)

If the mount hangs or shows as "already mounted," run this clean-up:

```bash
# 1. Stop the process
systemctl --user stop rclone-2ndbrain.service

# 2. Force Lazy Unmount
sudo umount -l ~/Documents/2ndBrain

# 3. Clear VFS Cache
rm -rf ~/.cache/rclone/vfs/gdrive-vault/

# 4. Restart
systemctl --user start rclone-2ndbrain.service
```

---

## 6. Portability (Moving to Machine 2)

To replicate this setup on a new machine:

```bash
old_machine="user@old_machine_ip"  # Replace with actual username and IP

# Install dependencies
sudo apt install rclone fuse3

# Create necessary directories
mkdir -p ~/.config/rclone
mkdir -p ~/Documents/2ndBrain

# Copy rclone config (contains OAuth tokens — keep it safe)
scp $old_machine:~/.config/rclone/rclone.conf ~/.config/rclone/

# Lock down permissions
chmod 600 ~/.config/rclone/rclone.conf
```

**Test the setup:**

```bash
# Verify rclone can see the remote
rclone listremotes   # Should show gdrive-vault:

# Run the installer
./install.sh --server   # or --workstation

# Check status
systemctl --user status rclone-2ndbrain.service
```

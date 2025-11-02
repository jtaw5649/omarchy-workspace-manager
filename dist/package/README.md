# Omarchy Workspace Manager

Shell utilities for orchestrating paired Hyprland workspaces. The toolkit keeps two monitors in sync, reassigns workspaces when displays appear or sleep, and ships helpers for installing keybindings, autostart fragments, and status bar refresh hooks.

## Features
- Pair primary and secondary monitors so `paired switch` and `paired cycle` move both displays together.
- Background daemon that watches Hyprland state and rebalances workspaces when monitors connect, disconnect, or change DPMS state.
- One-shot `dispatch` command to re-apply the configured workspace layout (with a `--dry-run` preview).
- `setup` helpers that render Hyprland binding/autostart fragments and keep them sourced from `$HOME/.config/hypr`.
- `checkpoints diff` to highlight drift between the packaged `config/paired.json` and the live Hyprland workspace cache.

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/jtaw5649/omarchy-workspace-manager/master/install.sh | bash
```

## Requirements
- Hyprland
- `curl` (or `wget`), `bash`, `jq`, `tar`, `pgrep`

## Quick Start
1. Clone the repository and run `./install.sh`. The installer stages the current build under `${OWM_INSTALL_DEST:-$HOME/.local/share/omarchy-workspace-manager}`, creates a launcher in `${OWM_INSTALL_BIN_DIR:-$HOME/.local/bin}`, and drops Hyprland fragments in `${OWM_INSTALL_CONFIG_DIR:-$HOME/.config/omarchy-workspace-manager}`. Adjust those destinations by exporting the corresponding `OWM_INSTALL_*` variables before running the script.
2. Ensure `${OWM_INSTALL_BIN_DIR}` is on your `PATH`, then try `omarchy-workspace-manager paired switch 3`.
3. Update `config/paired.json` to match your monitor names or rerun `omarchy-workspace-manager setup install --yes` after editing the file.

To remove the installation, run `scripts/uninstall.sh --yes`; it prunes staged versions, deletes the launcher, and removes generated Hyprland fragments.

## CLI Overview
- `paired switch <N>` – focus both monitors on the paired workspace index (respecting `--primary`, `--secondary`, `--offset`, `--no-waybar`).
- `paired cycle next|prev` – step through the paired workspace ring.
- `paired move-window <N>` – send the focused window to the paired index.
- `paired explain [--json]` – describe how the current workspace number resolves.
- `dispatch [--dry-run]` – reapply the configured workspace layout for both monitors.
- `daemon [--poll-interval 0.5]` – monitor Hyprland events and rebalance automatically.
- `setup install|uninstall` – generate or remove Hyprland binding/autostart fragments.
- `checkpoints diff [--json]` – compare expected workspace assignments with Hyprland’s persisted state.

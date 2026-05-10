# tmux-resurrect-named

Save and restore **named, per-session** snapshots on top of [tmux-resurrect].

Vanilla tmux-resurrect saves and restores the entire tmux server as one snapshot. This plugin lets you treat each session as an independent, named save slot — pick one from an `fzf` menu and only that session is restored.

## Features

- `prefix + S` — save the current session under a name you choose (defaults to the session's own name).
- `prefix + R` — open an `fzf-tmux` picker listing all named snapshots; selecting one restores it (or switches to it if it's already live).
- Optional background daemon that auto-splits tmux-resurrect's snapshot (e.g. one written by [tmux-continuum]) into per-session files, so saves stay current without you pressing anything.
- Best-effort `fzf` install via your system package manager if it's missing.

## Requirements

**Mandatory**

- **`tmux` ≥ 2.4** — needed for the `command-prompt -I` default-input syntax used by the save binding.
- **[tmux-resurrect]** — this plugin is a wrapper, not a replacement. It shells out to tmux-resurrect's `save.sh` and `restore.sh` to do the actual snapshotting. Install it via TPM or manually under `~/.tmux/plugins/tmux-resurrect`. If it lives elsewhere, set `@resurrect-named-scripts-dir`.
- **`fzf`** with the `fzf-tmux` wrapper — used by the restore picker. The plugin will best-effort install it on first restore via `pacman` / `apt-get` / `dnf` / `zypper` / `brew`, but only if non-interactive `sudo` is available; otherwise install it yourself.
- **`bash`** ≥ 4 — scripts use `[[`, arrays, `shopt -s nullglob`, and `set -euo pipefail`.
- **`awk`** — used to filter snapshots by session (any POSIX awk works: gawk, mawk, BSD awk).
- **`coreutils`** — `stat`, `wc`, `cut`, `sort`, `tr`, `sed`, `date`, `ln`, `mv`, `rm` (the auto-split daemon falls back to BSD `stat -f` if GNU `stat -c` isn't available, so macOS works).

**Optional**

- **[tmux-continuum]** — pairs well with `@resurrect-named-auto-split on`: continuum periodically refreshes tmux-resurrect's `last` snapshot, and the auto-split daemon then partitions it into per-session files automatically.
- **`sudo`** with passwordless config — only needed if you want the `fzf` auto-install to work non-interactively.

**Supported platforms**

- Linux and macOS. Should work anywhere tmux-resurrect itself works.

## Installation

### Using [TPM] (Tmux Plugin Manager)

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'dtutila/tmux-resurrect-named'
```

Then in tmux: `prefix + I` to fetch and source the plugin.

### Manual

```sh
git clone https://github.com/dtutila/tmux-resurrect-named ~/.tmux/plugins/tmux-resurrect-named
```

And add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-resurrect-named/resurrect-named.tmux
```

Reload tmux config: `tmux source-file ~/.tmux.conf`.

## Usage

| Key | Action |
|---|---|
| `prefix + S` | Prompt for a name and save the **current** session as a named snapshot. The default name is the session's own name — press Enter to accept. |
| `prefix + R` | Open an `fzf` picker of all named snapshots; selecting one restores it. If a live session with that name already exists, switches to it instead. |

Snapshots are stored alongside tmux-resurrect's own data, as `session_<name>.txt` in `@resurrect-dir` (default: `~/.local/share/tmux/resurrect`).

## Configuration

All options are tmux user-options set with `set -g`.

| Option | Default | Description |
|---|---|---|
| `@resurrect-named-save-key` | `S` | Key (after `prefix`) bound to save. |
| `@resurrect-named-restore-key` | `R` | Key (after `prefix`) bound to restore. |
| `@resurrect-named-auto-split` | _(off)_ | Set to `on` to start the background daemon that splits tmux-resurrect's snapshot into per-session files when it changes. |
| `@resurrect-named-auto-split-interval` | `30` | Poll interval in seconds for the auto-split daemon. |
| `@resurrect-named-scripts-dir` | `~/.tmux/plugins/tmux-resurrect/scripts` | Override the path to tmux-resurrect's scripts directory (e.g. if installed via Nix or a non-TPM location). |
| `@resurrect-dir` | `~/.local/share/tmux/resurrect` | Inherited from tmux-resurrect; this plugin reads/writes from the same directory. |

Example:

```tmux
set -g @resurrect-named-save-key 'C'
set -g @resurrect-named-restore-key 'V'
set -g @resurrect-named-auto-split 'on'
set -g @resurrect-named-auto-split-interval '60'
```

## How it works

- **Save** — calls `tmux-resurrect/scripts/save.sh` to produce a fresh full snapshot, then filters it down to lines (`pane`, `window`, `state`, `grouped_session`) belonging to the current session, and writes the result to `session_<name>.txt`.
- **Restore** — temporarily points tmux-resurrect's `last` symlink at the chosen `session_<name>.txt`, runs `tmux-resurrect/scripts/restore.sh`, then restores the original `last` pointer. tmux-resurrect itself does the actual session/window/pane recreation.
- **Auto-split** — a background poller watches the mtime of `last` and, when it changes, partitions it into per-session files. One instance per tmux server, guarded by a PID file.

## Troubleshooting

- **`tmux-resurrect not found at …`** — set `@resurrect-named-scripts-dir` to your install path.
- **`fzf-tmux not installed`** — install `fzf` manually (the auto-install only works with non-interactive `sudo`).
- **Nothing in the picker** — you haven't saved anything yet, or `@resurrect-dir` differs from where snapshots live.
- **Auto-split doesn't run** — it exits silently if another instance is already running for this tmux server. Remove `~/.local/share/tmux/resurrect/.named-split.pid` if you suspect a stale lock.

## Credits & References

This plugin would not exist without the work it sits on top of:

- **[tmux-resurrect]** by Bruno Sutic and contributors — the underlying save/restore engine. This plugin is a thin wrapper around its `save.sh` and `restore.sh`. ([tmux-plugins/tmux-resurrect][tmux-resurrect])
- **[tmux-continuum]** by Bruno Sutic and contributors — pairs naturally with the auto-split daemon for hands-off periodic saves. ([tmux-plugins/tmux-continuum][tmux-continuum])
- **[TPM]** (Tmux Plugin Manager) — the install path most users will take. ([tmux-plugins/tpm][TPM])
- **[fzf]** by Junegunn Choi — powers the restore picker via `fzf-tmux`. ([junegunn/fzf][fzf])

Snapshot file format, the `last` symlink convention, and the `pane`/`window`/`state`/`grouped_session` line schema all come from tmux-resurrect — see its `scripts/save.sh` and `scripts/restore.sh` for the source of truth.

### Development credits

This plugin was vibe-coded with assistance from **[Claude Code]** (Anthropic) — Claude helped with the snapshot-filtering logic, the auto-split daemon, the restore-via-`last`-symlink trick, and this documentation.

[fzf]: https://github.com/junegunn/fzf
[Claude Code]: https://claude.com/claude-code

## License

[MIT](LICENSE) © dtutila

[tmux-resurrect]: https://github.com/tmux-plugins/tmux-resurrect
[tmux-continuum]: https://github.com/tmux-plugins/tmux-continuum
[TPM]: https://github.com/tmux-plugins/tpm

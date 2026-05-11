# tmux-resurrect-named

Save and restore **named, per-session** snapshots on top of [tmux-resurrect].

Vanilla tmux-resurrect saves and restores the entire tmux server as one snapshot. This plugin lets you treat each session as an independent, named save slot — pick one from an `fzf` menu and only that session is restored.

## Features

- `prefix + S` — save the current session under a name you choose (defaults to the session's own name).
- `prefix + R` — open an `fzf-tmux` picker listing all named snapshots; selecting one restores it (or switches to it if it's already live).
- Optional background daemon that auto-splits tmux-resurrect's snapshot (e.g. one written by [tmux-continuum]) into per-session files, so saves stay current without you pressing anything.

## Requirements

**Mandatory**

- **`tmux` ≥ 3.2** — the restore picker uses `fzf-tmux -p`, which requires tmux's `display-popup` (added in 3.2). The save binding uses `command-prompt -I` (added in 2.4), so 3.2 covers everything.
- **[tmux-resurrect]** — this plugin is a wrapper, not a replacement. It shells out to tmux-resurrect's `save.sh` and `restore.sh` to do the actual snapshotting. Install it via TPM or manually under `~/.tmux/plugins/tmux-resurrect`. If it lives elsewhere, set `@resurrect-named-scripts-dir`.
- **`fzf` ≥ 0.50** with the `fzf-tmux` wrapper — the picker uses `transform`, `transform-prompt`, and `transform-header` actions (all available in 0.50+). Install via your system package manager (`pacman -S fzf`, `apt install fzf`, `dnf install fzf`, `brew install fzf`, …). On a few older distros (Debian bullseye, Ubuntu 22.04) the packaged fzf is too old — use [the upstream installer](https://github.com/junegunn/fzf#using-git) instead. On most distros the `fzf` package ships `fzf-tmux` on `$PATH`; on older Debian you may need to symlink it from `/usr/share/doc/fzf/examples/fzf-tmux`.
- **`bash`** ≥ 4 — scripts use `[[`, arrays, `shopt -s nullglob`, and `set -euo pipefail`.
- **`awk`** — used to filter snapshots by session (any POSIX awk works: gawk, mawk, BSD awk).
- **`coreutils`** — `stat`, `wc`, `cut`, `sort`, `tr`, `sed`, `date`, `ln`, `mv`, `rm` (the auto-split daemon falls back to BSD `stat -f` if GNU `stat -c` isn't available, so macOS works).

**Optional**

- **[tmux-continuum]** — pairs well with `@resurrect-named-auto-split on`: continuum periodically refreshes tmux-resurrect's `last` snapshot, and the auto-split daemon then partitions it into per-session files automatically.

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

## First run

After installing on a new machine, walk through this once to confirm everything's wired up:

1. **Reload tmux config** (or restart tmux) so the bindings load:
   ```sh
   tmux source-file ~/.tmux.conf
   ```
   With TPM, `prefix + I` fetches plugins and sources them in one step.

2. **Save your first snapshot.** In any tmux session, press `prefix + S`. The prompt pre-fills with the current session's name; press Enter to accept (or edit, then Enter). The status line should report something like `saved 'main' as 'main' — 2 win, 5 pane(s)`.

3. **Open the picker.** Press `prefix + R`. An `fzf-tmux` popup appears listing your snapshots, including ones for tmux's auto-named numeric sessions (`0`, `1`, …). If you'd rather hide those by default and focus on names you chose, set `@resurrect-named-hide-numeric on` (and toggle back with `alt-h` inside the picker).

If `prefix + R` does nothing, opens an empty popup, or flashes and closes, see [Troubleshooting](#troubleshooting) below.

## Usage

| Key | Action |
|---|---|
| `prefix + S` | Prompt for a name and save the **current** session as a named snapshot. The default name is the session's own name — press Enter to accept. |
| `prefix + R` | Open an `fzf` picker of all named snapshots; selecting one restores it. If a live session with that name already exists, switches to it instead. |

Inside the `prefix + R` picker:

| Key | Action |
|---|---|
| `Enter` | Restore the snapshot, or switch to it if it's already live. |
| `ctrl-d` | Delete the highlighted snapshot (asks `y/N` first). |
| `ctrl-e` | Rename the highlighted snapshot (prompts for a new name). |
| `ctrl-x` | Kill the highlighted live session (asks `y/N` first; no-op if not live). |
| `alt-h` | Toggle between **all** (default) and **named-only** snapshots. tmux gives unnamed sessions numeric names (`0`, `1`, …); set `@resurrect-named-hide-numeric on` to hide those by default. The prompt shows the current mode. |

A `●` next to a row means a live session with that name exists. The right-side preview pane shows the snapshot's mtime, size, window/pane count, and the first pane's command.

Snapshots are stored alongside tmux-resurrect's own data, as `session_<name>.txt` in `@resurrect-dir` (default: `~/.local/share/tmux/resurrect`).

## Configuration

All options are tmux user-options set with `set -g`.

| Option | Default | Description |
|---|---|---|
| `@resurrect-named-save-key` | `S` | Key (after `prefix`) bound to save. |
| `@resurrect-named-restore-key` | `R` | Key (after `prefix`) bound to restore. |
| `@resurrect-named-auto-split` | _(off)_ | Set to `on` to start the background daemon that splits tmux-resurrect's snapshot into per-session files when it changes. |
| `@resurrect-named-auto-split-interval` | `30` | Poll interval in seconds for the auto-split daemon. |
| `@resurrect-named-auto-save-on-switch` | _(off)_ | Set to `on` to automatically save the current session (under its own name) before the picker switches to or restores another. Handy if you want hands-off snapshotting when hopping between sessions. |
| `@resurrect-named-hide-numeric` | _(off)_ | Set to `on` to hide snapshots whose name is purely numeric (`0`, `1`, …) by default in the picker. tmux auto-assigns those names to unnamed sessions; hiding them focuses the picker on names you chose. `alt-h` still toggles either way. |
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

## Versioning

This plugin follows [Semantic Versioning](https://semver.org/) via `vX.Y.Z` git tags, matching the convention used by [tmux-resurrect], [tmux-continuum], and [TPM]. See [`CHANGELOG.md`](CHANGELOG.md) for release notes.

To pin to a specific release with TPM:

```tmux
set -g @plugin 'dtutila/tmux-resurrect-named#v0.1.0'
```

Without `#tag`, TPM tracks the default branch.

## Troubleshooting

- **`tmux-resurrect not found at …`** — set `@resurrect-named-scripts-dir` to your install path.
- **`fzf-tmux not found`** — install `fzf` via your system package manager (`apt`, `dnf`, `pacman`, `brew`, …). If the packaged version is `< 0.50`, install from upstream instead.
- **Picker shows "no snapshots yet"** — you haven't saved anything yet. Press `prefix + S` to create your first snapshot. (Also check that `@resurrect-dir` matches where snapshots actually live.)
- **Picker looks empty even though `session_*.txt` files exist** — if you set `@resurrect-named-hide-numeric on`, all-numeric names (`session_0.txt`, `session_1.txt`, …) are hidden. Press `alt-h` to toggle to `all` mode, or rename them with `ctrl-e` from inside the picker.
- **`prefix + R` does nothing / flashes and closes** — usually means the plugin loaded but tmux hasn't re-sourced after a fresh install. Run `tmux source-file ~/.tmux.conf` (or `prefix + I` if using TPM), or detach and start a new tmux session. If it persists, check that `fzf --version` reports ≥ 0.50 and `tmux -V` reports ≥ 3.2.
- **Picker error mentions `transform` / unknown action** — your fzf is too old. Upgrade to 0.50+.
- **Auto-split doesn't run** — it exits silently if another instance is already running for this tmux server. Remove `~/.local/share/tmux/resurrect/.named-split.pid` if you suspect a stale lock.

For deeper debugging, run the picker manually to see errors that tmux's status line might swallow:

```sh
bash -x ~/.tmux/plugins/tmux-resurrect-named/scripts/restore_named.sh 2>&1 | tail -40
```

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

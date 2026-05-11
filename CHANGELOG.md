# Changelog

This project follows [Semantic Versioning](https://semver.org/) and the TPM-ecosystem convention of `vX.Y.Z` git tags (see [tmux-resurrect][res-changes], [tmux-continuum][cont-changes], [tpm][tpm-changes]).

### Unreleased

- **Default filter is now `all`** — numeric-name snapshots (auto-named tmux
  sessions `0`, `1`, …) are shown in the picker by default. Set the new
  `@resurrect-named-hide-numeric on` option to restore the old "hide
  numerics" default. `alt-h` still toggles either way.
- Session management inside the `prefix + R` fzf picker:
  - `ctrl-d` — delete the highlighted snapshot (with confirmation)
  - `ctrl-e` — rename the highlighted snapshot
  - `ctrl-x` — kill the highlighted live session (with confirmation)
  - Live-vs-snapshot marker (`●`) per row
  - Right-side preview pane with name, mtime, size, window/pane counts, first command
- Hide numeric-name (unnamed-tmux-session) snapshots in the picker by default; toggle with `alt-h`. Prompt label (`named>` / `all>`) reflects the current mode.
- Picker UX:
  - Header toggle label is dynamic — shows `alt-h:show-all` in named mode and `alt-h:hide-numeric` in all mode, so it always describes what pressing it will do next.
  - When every existing snapshot has a numeric name, the picker now opens in `all` mode automatically (with a one-line hint) instead of presenting an empty list.
  - `prefix + R` with no snapshots now hints at `prefix + S` instead of just reporting the empty directory.
  - Delete, rename, and kill actions emit a tmux status message after the picker closes so successful operations are visible.
- Save UX:
  - Success message now reports window/pane counts instead of raw line counts, and notes when an existing snapshot was replaced.
  - Snapshots are written via a tmp-file + atomic `mv`, so a failed/empty filter no longer clobbers the previous snapshot.
- New option `@resurrect-named-auto-save-on-switch` (off by default) — when on, the picker auto-saves the current session under its own name before switching/restoring.
- Picker live marker is now green (ANSI 32), with a trailing space so names
  always sit a column away from the dot.
- Removed the best-effort `fzf` auto-install on first restore. The plugin now
  prints a one-line install hint instead of attempting `sudo` package-manager
  invocations behind your back. Install `fzf` via your package manager.
- Internals:
  - `last` symlink swap during restore is now signal-safe (trapped on INT/TERM/HUP).
  - `eval echo` in tmux-option expansion replaced with safe tilde expansion.
  - `$SELF` is now quoted inside fzf bind strings so install paths with spaces work.
- Docs:
  - New **First run** section walks through reload → save → restore, with the numeric-name gotcha called out.
  - Requirements section now states the real minimums: tmux ≥ 3.2 (for `display-popup` used by `fzf-tmux -p`) and fzf ≥ 0.50 (for the `transform`/`transform-prompt`/`transform-header` actions the picker uses).
  - Troubleshooting expanded with the `prefix + R does nothing / flashes and closes` case (usually plugin loaded but tmux not yet re-sourced on a fresh install), an explicit "all snapshots are numeric — press alt-h" hint, and a `bash -x` recipe for deeper debugging.

### v0.1.0 — 2026-05-10

- Initial release.
- `prefix + S` — save the current session as a named snapshot.
- `prefix + R` — `fzf-tmux` picker to restore a named snapshot, or switch to the live session if one with that name already exists.
- Optional `@resurrect-named-auto-split` background daemon that partitions tmux-resurrect's `last` snapshot into per-session files when it changes.
- Best-effort `fzf` install via `pacman` / `apt-get` / `dnf` / `zypper` / `brew` on first restore.
- Configurable save/restore keys, scripts directory, and auto-split poll interval.

[res-changes]: https://github.com/tmux-plugins/tmux-resurrect/blob/master/CHANGELOG.md
[cont-changes]: https://github.com/tmux-plugins/tmux-continuum/blob/master/CHANGELOG.md
[tpm-changes]: https://github.com/tmux-plugins/tpm/blob/master/CHANGELOG.md

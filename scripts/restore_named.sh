#!/usr/bin/env bash
# Pick a named snapshot via fzf and restore it (or switch to it if already running).
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

resurrect_dir=$(get_resurrect_dir)
resurrect_scripts=$(get_resurrect_scripts_dir)

if [ ! -x "$resurrect_scripts/restore.sh" ]; then
    display_message "resurrect-named: tmux-resurrect not found at $resurrect_scripts"
    exit 1
fi

if ! command -v fzf-tmux >/dev/null 2>&1; then
    "$CURRENT_DIR/ensure_fzf.sh" || true
fi
if ! command -v fzf-tmux >/dev/null 2>&1; then
    display_message "resurrect-named: fzf-tmux not installed (install 'fzf')"
    exit 1
fi

shopt -s nullglob
files=("$resurrect_dir"/session_*.txt)
if [ ${#files[@]} -eq 0 ]; then
    display_message "resurrect-named: no named snapshots in $resurrect_dir"
    exit 0
fi

list=""
for f in "${files[@]}"; do
    base=$(basename "$f" .txt)
    name="${base#session_}"
    mtime=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "")
    list+="$name"$'\t'"$mtime"$'\n'
done

set +e
selection=$(printf '%b' "$list" \
    | fzf-tmux -p 60%,40% \
        --with-nth=1,2 \
        --delimiter=$'\t' \
        --header="Restore named tmux session" \
        --no-multi)
fzf_status=$?
set -e
if [ $fzf_status -ne 0 ] || [ -z "$selection" ]; then
    exit 0
fi

name=$(printf '%s' "$selection" | cut -f1)
[ -z "$name" ] && exit 0

# If a live session with this name exists, switch to it instead of restoring.
if tmux has-session -t "=$name" 2>/dev/null; then
    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "=$name"
    else
        tmux attach-session -t "=$name"
    fi
    exit 0
fi

snapshot_basename="session_${name}.txt"
snapshot="$resurrect_dir/$snapshot_basename"
if [ ! -f "$snapshot" ]; then
    display_message "resurrect-named: snapshot '$snapshot' not found"
    exit 1
fi

last_link="$resurrect_dir/last"
original=""
backup=""
# Stash the current `last` pointer; restore.sh always reads it, so we re-aim it temporarily.
if [ -L "$last_link" ]; then
    original=$(readlink "$last_link")
elif [ -e "$last_link" ]; then
    backup="$last_link.resurrect-named-backup.$$"
    mv "$last_link" "$backup"
fi

ln -sfn "$snapshot_basename" "$last_link"

set +e
"$resurrect_scripts/restore.sh" >/dev/null 2>&1
status=$?
set -e

# Restore previous `last` pointer so vanilla resurrect's history isn't disturbed.
if [ -n "$original" ]; then
    ln -sfn "$original" "$last_link"
elif [ -n "$backup" ] && [ -e "$backup" ]; then
    rm -f "$last_link"
    mv "$backup" "$last_link"
fi

if [ $status -eq 0 ]; then
    display_message "resurrect-named: restored session '$name'"
else
    display_message "resurrect-named: restore failed (status $status)"
fi

#!/usr/bin/env bash
# Save the current tmux session as a named snapshot. Args: [name]
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

raw_name="${1:-}"
[ -z "$raw_name" ] && raw_name=$(tmux display-message -p '#S')

name=$(sanitize_name "$raw_name")
if [ -z "$name" ]; then
    display_message "resurrect-named: invalid empty name"
    exit 1
fi

current_session=$(tmux display-message -p '#S')
resurrect_dir=$(get_resurrect_dir)
resurrect_scripts=$(get_resurrect_scripts_dir)

if [ ! -x "$resurrect_scripts/save.sh" ]; then
    display_message "resurrect-named: tmux-resurrect not found at $resurrect_scripts"
    exit 1
fi

# Trigger a fresh full snapshot via vanilla resurrect; ignore failures so we still try to filter.
"$resurrect_scripts/save.sh" quiet >/dev/null 2>&1 || true

last_link="$resurrect_dir/last"
if [ ! -e "$last_link" ]; then
    display_message "resurrect-named: no snapshot produced by tmux-resurrect"
    exit 1
fi

target=$(named_snapshot_path "$name")
filter_snapshot_by_session "$last_link" "$current_session" "$target"

# Empty result means the session had no panes/windows in the snapshot — drop the file.
count=$(wc -l < "$target" | tr -d ' ')
if [ "${count:-0}" -eq 0 ]; then
    rm -f "$target"
    display_message "resurrect-named: nothing to save for session '$current_session'"
    exit 1
fi

display_message "resurrect-named: saved '$current_session' as '$name' ($count lines)"

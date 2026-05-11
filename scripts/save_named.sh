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
existed=0
[ -e "$target" ] && existed=1

# Write to a tmp file first so a failed/empty filter doesn't clobber an existing snapshot.
tmp="${target}.tmp.$$"
trap 'rm -f "$tmp"' EXIT
filter_snapshot_by_session "$last_link" "$current_session" "$tmp"

if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    display_message "resurrect-named: nothing to save for session '$current_session'"
    exit 1
fi

mv -f "$tmp" "$target"

read -r windows panes < <(count_snapshot_units "$target")
suffix=""
[ "$existed" = "1" ] && suffix=" (replaced)"
display_message "resurrect-named: saved '$current_session' as '$name' — ${windows} win, ${panes} pane(s)${suffix}"

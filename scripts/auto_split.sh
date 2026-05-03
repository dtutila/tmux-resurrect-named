#!/usr/bin/env bash
# Background poller: when tmux-resurrect's `last` snapshot changes (e.g. via
# tmux-continuum's periodic save), split it into per-session `session_*.txt`
# files. One instance per tmux server, guarded by a PID file.
set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

resurrect_dir=$(get_resurrect_dir)
mkdir -p "$resurrect_dir"

interval=$(tmux show-option -gqv "@resurrect-named-auto-split-interval")
case "$interval" in
    ''|*[!0-9]*) interval=30 ;;
esac

pidfile="$resurrect_dir/.named-split.pid"
mtime_file="$resurrect_dir/.named-split.last_mtime"

# Single-instance guard.
if [ -f "$pidfile" ]; then
    old_pid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$pidfile"
trap 'rm -f "$pidfile"' EXIT

stat_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

last="$resurrect_dir/last"

while true; do
    sleep "$interval"

    # Exit cleanly when tmux server is gone.
    tmux info >/dev/null 2>&1 || exit 0

    [ -e "$last" ] || continue
    cur=$(stat_mtime "$last")
    [ -z "${cur:-}" ] && continue
    prev=$(cat "$mtime_file" 2>/dev/null || echo 0)
    [ "$cur" = "$prev" ] && continue

    sessions=$(awk -F'\t' '
        ($1 == "pane" || $1 == "window") && $2 != "" { print $2 }
    ' "$last" | sort -u)

    for sess in $sessions; do
        [ -z "$sess" ] && continue
        safe=$(sanitize_name "$sess")
        [ -z "$safe" ] && continue
        target="$resurrect_dir/session_${safe}.txt"
        tmp="$target.tmp.$$"
        filter_snapshot_by_session "$last" "$sess" "$tmp"
        if [ -s "$tmp" ]; then
            mv -f "$tmp" "$target"
        else
            rm -f "$tmp"
        fi
    done

    echo "$cur" > "$mtime_file"
done

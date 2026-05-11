#!/usr/bin/env bash
# Shared helpers sourced by save/restore/auto-split scripts.

# Expand a leading `~` / `~/` to $HOME without invoking eval (safe against
# tmux-option values that contain $(), backticks, or shell metacharacters).
expand_tilde() {
    local p="$1"
    case "$p" in
        '~')   printf '%s' "$HOME" ;;
        '~/'*) printf '%s/%s' "$HOME" "${p#~/}" ;;
        *)     printf '%s' "$p" ;;
    esac
}

# Snapshot directory; mirrors tmux-resurrect's @resurrect-dir so both plugins agree.
get_resurrect_dir() {
    local dir
    dir=$(tmux show-option -gqv "@resurrect-dir")
    [ -z "$dir" ] && dir="$HOME/.local/share/tmux/resurrect"
    expand_tilde "$dir"
}

# Path to vanilla tmux-resurrect's scripts; overridable for non-TPM installs.
get_resurrect_scripts_dir() {
    local override
    override=$(tmux show-option -gqv "@resurrect-named-scripts-dir")
    if [ -n "$override" ]; then
        expand_tilde "$override"
    else
        echo "$HOME/.tmux/plugins/tmux-resurrect/scripts"
    fi
}

named_snapshot_path() {
    local name="$1"
    local dir
    dir=$(get_resurrect_dir)
    echo "$dir/session_${name}.txt"
}

display_message() {
    [ "${RNAMED_QUIET:-}" = "1" ] && return 0
    tmux display-message "$1"
}

# Filter a snapshot to lines belonging to a single session.
# Args: <input> <session_name> <output>
filter_snapshot_by_session() {
    local input="$1" session="$2" output="$3"
    # Rewrite `state` to point at <session> so restore.sh attaches to the right one.
    awk -F'\t' -v s="$session" '
        BEGIN { OFS = "\t" }
        $1 == "pane"   && $2 == s { print; next }
        $1 == "window" && $2 == s { print; next }
        $1 == "state"             { print "state", s, s; next }
        $1 == "grouped_session" && ($2 == s || $3 == s) { print; next }
    ' "$input" > "$output"
}

# Strip filesystem-unsafe chars from a name (snapshot filename is derived from it).
sanitize_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | sed 's/^_*//; s/_*$//'
}

is_session_live() {
    tmux has-session -t "=$1" 2>/dev/null
}

# Count windows/panes in a snapshot file. Output: "<windows> <panes>" (space-separated).
count_snapshot_units() {
    awk -F'\t' '
        $1 == "window" { w++ }
        $1 == "pane"   { p++ }
        END { printf "%d %d", w+0, p+0 }
    ' "$1"
}

# tmux's default name for unnamed sessions is the numeric index — those snapshots
# clutter the picker, so we hide them unless the user toggles them on.
is_numeric_name() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Print a short, human-readable summary of a snapshot file. Used by the fzf
# preview pane, so output is kept narrow.
summarize_snapshot() {
    local file="$1" name="$2"
    local mtime size live_marker

    if is_session_live "$name"; then
        live_marker=$'\e[32m●\e[0m live'
    else
        live_marker="snapshot only"
    fi

    mtime=$(date -r "$file" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "?")
    if size=$(stat -c %s "$file" 2>/dev/null); then :; else
        size=$(stat -f %z "$file" 2>/dev/null || echo 0)
    fi

    printf '%s     %s\n' "$name" "$live_marker"
    printf 'saved:     %s  (%s bytes)\n' "$mtime" "$size"
    printf '\n'
    # The snapshot file is already filtered to a single session — its inner
    # session name may differ from the picker label (e.g. saved while in
    # session "bounty" but stored under the label "tpm"), so count any line.
    awk -F'\t' '
        $1 == "window" { w++ }
        $1 == "pane"   { p++; if (!fc) fc = $NF }
        END {
            printf "windows:   %d\n", w+0
            printf "panes:     %d\n", p+0
            if (fc != "") printf "first cmd: %s\n", fc
        }
    ' "$file"
}

#!/usr/bin/env bash

get_resurrect_dir() {
    local dir
    dir=$(tmux show-option -gqv "@resurrect-dir")
    [ -z "$dir" ] && dir="$HOME/.local/share/tmux/resurrect"
    eval echo "$dir"
}

get_resurrect_scripts_dir() {
    local override
    override=$(tmux show-option -gqv "@resurrect-named-scripts-dir")
    if [ -n "$override" ]; then
        eval echo "$override"
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
    tmux display-message "$1"
}

# Filter a snapshot to lines belonging to a single session.
# Args: <input> <session_name> <output>
filter_snapshot_by_session() {
    local input="$1" session="$2" output="$3"
    awk -F'\t' -v s="$session" '
        BEGIN { OFS = "\t" }
        $1 == "pane"   && $2 == s { print; next }
        $1 == "window" && $2 == s { print; next }
        $1 == "state"             { print "state", s, s; next }
        $1 == "grouped_session" && ($2 == s || $3 == s) { print; next }
    ' "$input" > "$output"
}

# Strip filesystem-unsafe chars from a name.
sanitize_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | sed 's/^_*//; s/_*$//'
}

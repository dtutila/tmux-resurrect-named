#!/usr/bin/env bash
# Pick a named snapshot via fzf and restore it (or switch to it if already running).
# Self-dispatching: subcommands (--list, --preview, --delete, --rename, --kill,
# --toggle-filter, --prompt, --header, --y-action, --n-action, --enter-action,
# --arm, --confirm-pending, --clear-pending) are used internally by the fzf
# picker for live management.
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

SELF="$CURRENT_DIR/restore_named.sh"

# Header is rebuilt per-keystroke so the toggle label always reflects what
# pressing it will do *next* (show-all when in named mode, hide-numeric in all).
# ctrl-t and alt-h are both bound to the toggle; ctrl-t is the primary because
# alt-key delivery is unreliable on some terminals/tmux setups.
header_for_filter() {
    local toggle_label
    if [ "${1:-named}" = "named" ]; then
        toggle_label='ctrl-t:show-all'
    else
        toggle_label='ctrl-t:hide-numeric'
    fi
    printf 'enter:restore  ctrl-d:del  ctrl-e:rename  ctrl-x:kill  %s' "$toggle_label"
}

cmd_list() {
    local resurrect_dir filter mode_file
    resurrect_dir=$(get_resurrect_dir)
    mode_file="${RNAMED_STATE:-}"
    if [ -n "$mode_file" ] && [ -f "$mode_file" ]; then
        filter=$(cat "$mode_file")
    else
        filter="all"
    fi

    shopt -s nullglob
    local f base name mtime marker
    for f in "$resurrect_dir"/session_*.txt; do
        base=$(basename "$f" .txt)
        name="${base#session_}"
        if [ "$filter" = "named" ] && is_numeric_name "$name"; then
            continue
        fi
        mtime=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "")
        if is_session_live "$name"; then
            marker=$'\e[32m●\e[0m '
        else
            marker="  "
        fi
        printf '%s\t%s\t%s\n' "$name" "$mtime" "$marker"
    done
}

cmd_preview() {
    local name="${1:-}"
    [ -z "$name" ] && return 0
    local file
    file=$(named_snapshot_path "$name")
    if [ ! -f "$file" ]; then
        printf 'snapshot file missing: %s\n' "$file"
        return 0
    fi
    summarize_snapshot "$file" "$name"
}

# Non-interactive delete; the picker confirms inline before calling this.
cmd_delete() {
    local name="${1:-}"
    [ -z "$name" ] && return 0
    local file
    file=$(named_snapshot_path "$name")
    if [ -f "$file" ] && rm -f "$file"; then
        display_message "resurrect-named: deleted snapshot '$name'"
    fi
}

# Interactive rename via fzf's execute() tty takeover; called from the picker on ctrl-e.
cmd_rename() {
    local name="${1:-}"
    [ -z "$name" ] && return 0
    local src
    src=$(named_snapshot_path "$name")
    if [ ! -f "$src" ]; then
        printf "no snapshot for '%s'\n" "$name"
        return 0
    fi
    local raw new dst
    read -r -p "new name (was '$name'): " raw || return 0
    new=$(sanitize_name "$raw")
    if [ -z "$new" ]; then
        printf 'invalid empty name\n'
        return 0
    fi
    if [ "$new" = "$name" ]; then
        printf 'name unchanged\n'
        return 0
    fi
    dst=$(named_snapshot_path "$new")
    if [ -e "$dst" ]; then
        printf "'%s' already exists; refusing to overwrite\n" "$new"
        return 0
    fi
    mv -- "$src" "$dst"
    printf 'renamed %s -> %s\n' "$name" "$new"
    display_message "resurrect-named: renamed '$name' → '$new'"
}

# Non-interactive kill; the picker confirms inline before calling this.
cmd_kill() {
    local name="${1:-}"
    [ -z "$name" ] && return 0
    is_session_live "$name" || return 0
    if tmux kill-session -t "=$name" 2>/dev/null; then
        display_message "resurrect-named: killed live session '$name'"
    fi
}

cmd_toggle_filter() {
    local f cur
    f="${RNAMED_STATE:-}"
    [ -z "$f" ] && return 0
    cur=$(cat "$f" 2>/dev/null || echo all)
    if [ "$cur" = "named" ]; then
        echo all > "$f"
    else
        echo named > "$f"
    fi
}

# --- inline confirmation helpers (called by fzf transform/transform-prompt/transform-header) ---

current_filter() {
    local f
    f="${RNAMED_STATE:-}"
    if [ -n "$f" ] && [ -s "$f" ]; then
        cat "$f"
    else
        echo all
    fi
}

pending_armed() {
    [ -n "${RNAMED_PENDING:-}" ] && [ -s "${RNAMED_PENDING}" ]
}

cmd_prompt() {
    if pending_armed; then
        local pending action name
        pending=$(cat "$RNAMED_PENDING")
        action="${pending%%:*}"
        name="${pending#*:}"
        case "$action" in
            delete) printf "delete '%s'? [y/N]> " "$name" ;;
            kill)   printf "kill live '%s'? [y/N]> " "$name" ;;
            *)      printf '%s> ' "$(current_filter)" ;;
        esac
    else
        printf '%s> ' "$(current_filter)"
    fi
}

cmd_header() {
    if pending_armed; then
        printf 'press y to confirm, n or Enter to cancel'
    else
        header_for_filter "$(current_filter)"
    fi
}

cmd_arm() {
    local action="${1:-}" name="${2:-}"
    [ -z "$action" ] || [ -z "$name" ] && return 0
    [ -z "${RNAMED_PENDING:-}" ] && return 0

    # Validate before arming so transform-prompt/header only show "[y/N]" for
    # actions that can actually run. On rejection we display a tmux message
    # instead — the picker stays in its normal state.
    case "$action" in
        delete)
            local file
            file=$(named_snapshot_path "$name")
            if [ ! -f "$file" ]; then
                display_message "resurrect-named: no snapshot named '$name'"
                return 0
            fi
            ;;
        kill)
            if ! is_session_live "$name"; then
                display_message "resurrect-named: no live session '$name'"
                return 0
            fi
            local cur
            cur=$(tmux display-message -p '#S' 2>/dev/null || echo "")
            if [ -n "$cur" ] && [ "$cur" = "$name" ]; then
                display_message "resurrect-named: refusing to kill current session '$name'"
                return 0
            fi
            ;;
    esac

    printf '%s:%s' "$action" "$name" > "$RNAMED_PENDING"
}

cmd_clear_pending() {
    [ -n "${RNAMED_PENDING:-}" ] && : > "$RNAMED_PENDING"
}

cmd_confirm_pending() {
    pending_armed || return 0
    local pending action name
    pending=$(cat "$RNAMED_PENDING")
    action="${pending%%:*}"
    name="${pending#*:}"
    : > "$RNAMED_PENDING"
    case "$action" in
        delete) cmd_delete "$name" ;;
        kill)   cmd_kill   "$name" ;;
    esac
}

# y/n/enter dispatch via `transform` so we can branch on whether a delete/kill
# is armed without ever unbinding the keys (unbind would also drop the *default*
# action, so e.g. unbind(enter) breaks the primary "press Enter to restore" path).
# When nothing is armed, y and n type into the search query (default fzf
# behavior) and Enter accepts (restores the highlighted snapshot).
cmd_y_action() {
    if pending_armed; then
        printf 'execute-silent(%s --confirm-pending)+reload(%s --list)+transform-prompt(%s --prompt)+transform-header(%s --header)' \
            "$SELF" "$SELF" "$SELF" "$SELF"
    else
        printf 'put(y)'
    fi
}

cmd_n_action() {
    if pending_armed; then
        printf 'execute-silent(%s --clear-pending)+transform-prompt(%s --prompt)+transform-header(%s --header)' \
            "$SELF" "$SELF" "$SELF"
    else
        printf 'put(n)'
    fi
}

cmd_enter_action() {
    if pending_armed; then
        printf 'execute-silent(%s --clear-pending)+transform-prompt(%s --prompt)+transform-header(%s --header)' \
            "$SELF" "$SELF" "$SELF"
    else
        printf 'accept'
    fi
}

# Optional: save the current session under its tmux name before switching/restoring.
auto_save_current_session() {
    local opt cur
    opt=$(tmux show-option -gqv "@resurrect-named-auto-save-on-switch" 2>/dev/null || true)
    [ "$opt" = "on" ] || return 0
    [ -n "${TMUX:-}" ] || return 0
    cur=$(tmux display-message -p '#S' 2>/dev/null || true)
    [ -n "$cur" ] || return 0
    [ "$cur" = "${1:-}" ] && return 0  # picking same session — no save
    RNAMED_QUIET=1 "$CURRENT_DIR/save_named.sh" "$cur" >/dev/null 2>&1 || true
}

cmd_picker() {
    local resurrect_dir resurrect_scripts
    resurrect_dir=$(get_resurrect_dir)
    resurrect_scripts=$(get_resurrect_scripts_dir)

    if [ ! -x "$resurrect_scripts/restore.sh" ]; then
        display_message "resurrect-named: tmux-resurrect not found at $resurrect_scripts"
        exit 1
    fi

    if ! command -v fzf-tmux >/dev/null 2>&1; then
        display_message "resurrect-named: fzf-tmux not found — install 'fzf' (e.g. pacman/apt/dnf/brew install fzf)"
        exit 1
    fi

    shopt -s nullglob
    local files=("$resurrect_dir"/session_*.txt)
    if [ ${#files[@]} -eq 0 ]; then
        display_message "resurrect-named: no snapshots yet — press prefix+S to save the current session"
        exit 0
    fi

    # Per-invocation state. Exported so child shells (fzf execute/reload/transform)
    # see the same files. Cleaned up on exit.
    RNAMED_STATE=$(mktemp)
    RNAMED_PENDING=$(mktemp)
    trap 'rm -f "$RNAMED_STATE" "$RNAMED_PENDING"' EXIT

    # Initial filter: `all` shows every snapshot; `named` hides numeric-name
    # (unnamed-tmux-session) snapshots. Default is `all` so picker shows
    # everything; opt in to hiding numerics via @resurrect-named-hide-numeric.
    local initial_filter="all"
    local hide_numeric
    hide_numeric=$(tmux show-option -gqv "@resurrect-named-hide-numeric" 2>/dev/null || true)
    if [ "$hide_numeric" = "on" ]; then
        initial_filter="named"
        # Avoid opening into an empty picker when every snapshot is numeric.
        local any_named=0 f base nm
        for f in "${files[@]}"; do
            base=$(basename "$f" .txt); nm="${base#session_}"
            if ! is_numeric_name "$nm"; then any_named=1; break; fi
        done
        if [ "$any_named" = "0" ]; then
            initial_filter="all"
            display_message "resurrect-named: only numeric-name snapshots — showing all (alt-h to toggle)"
        fi
    fi
    echo "$initial_filter" > "$RNAMED_STATE"
    : > "$RNAMED_PENDING"
    export RNAMED_STATE RNAMED_PENDING

    local prompt_label header_text
    prompt_label="${initial_filter}> "
    header_text=$(header_for_filter "$initial_filter")

    local selection fzf_status
    set +e
    selection=$(fzf-tmux -p 80%,60% \
        --ansi \
        --delimiter=$'\t' \
        --with-nth=3,1,2 \
        --prompt="$prompt_label" \
        --header="$header_text" \
        --no-multi \
        --preview "'$SELF' --preview {1}" \
        --preview-window=right,40%,wrap \
        --bind "ctrl-d:execute-silent('$SELF' --arm delete {1})+transform-prompt('$SELF' --prompt)+transform-header('$SELF' --header)" \
        --bind "ctrl-x:execute-silent('$SELF' --arm kill {1})+transform-prompt('$SELF' --prompt)+transform-header('$SELF' --header)" \
        --bind "ctrl-e:execute-silent('$SELF' --clear-pending)+execute('$SELF' --rename {1})+reload('$SELF' --list)+transform-prompt('$SELF' --prompt)+transform-header('$SELF' --header)" \
        --bind "ctrl-t:execute-silent('$SELF' --toggle-filter)+execute-silent('$SELF' --clear-pending)+reload('$SELF' --list)+transform-prompt('$SELF' --prompt)+transform-header('$SELF' --header)" \
        --bind "alt-h:execute-silent('$SELF' --toggle-filter)+execute-silent('$SELF' --clear-pending)+reload('$SELF' --list)+transform-prompt('$SELF' --prompt)+transform-header('$SELF' --header)" \
        --bind "y:transform('$SELF' --y-action)" \
        --bind "n:transform('$SELF' --n-action)" \
        --bind "enter:transform('$SELF' --enter-action)" \
        < <("$SELF" --list))
    fzf_status=$?
    set -e
    if [ $fzf_status -ne 0 ] || [ -z "$selection" ]; then
        exit 0
    fi

    local name
    name=$(printf '%s' "$selection" | cut -f1)
    [ -z "$name" ] && exit 0

    auto_save_current_session "$name"

    # If a live session with this name exists, switch to it instead of restoring.
    if is_session_live "$name"; then
        if [ -n "${TMUX:-}" ]; then
            tmux switch-client -t "=$name"
        else
            tmux attach-session -t "=$name"
        fi
        exit 0
    fi

    local snapshot_basename="session_${name}.txt"
    local snapshot="$resurrect_dir/$snapshot_basename"
    if [ ! -f "$snapshot" ]; then
        display_message "resurrect-named: snapshot '$snapshot' not found"
        exit 1
    fi

    local last_link="$resurrect_dir/last"
    local original=""
    local backup=""
    # Stash the current `last` pointer; restore.sh always reads it, so we re-aim it temporarily.
    if [ -L "$last_link" ]; then
        original=$(readlink "$last_link")
    elif [ -e "$last_link" ]; then
        backup="$last_link.resurrect-named-backup.$$"
        mv "$last_link" "$backup"
    fi

    # Make the swap signal-safe: if we get killed mid-restore, don't leave
    # vanilla resurrect's `last` pointing at the per-session snapshot.
    restore_last_link() {
        if [ -n "$original" ]; then
            ln -sfn "$original" "$last_link"
        elif [ -n "$backup" ] && [ -e "$backup" ]; then
            rm -f "$last_link"
            mv "$backup" "$last_link"
        fi
    }
    trap 'restore_last_link; rm -f "$RNAMED_STATE" "$RNAMED_PENDING"' EXIT INT TERM HUP

    ln -sfn "$snapshot_basename" "$last_link"

    local status
    set +e
    "$resurrect_scripts/restore.sh" >/dev/null 2>&1
    status=$?
    set -e

    restore_last_link
    trap 'rm -f "$RNAMED_STATE" "$RNAMED_PENDING"' EXIT

    if [ $status -eq 0 ]; then
        display_message "resurrect-named: restored session '$name'"
    else
        display_message "resurrect-named: restore failed (status $status)"
    fi
}

case "${1:-}" in
    --list)             cmd_list ;;
    --preview)          cmd_preview "${2:-}" ;;
    --delete)           cmd_delete "${2:-}" ;;
    --rename)           cmd_rename "${2:-}" ;;
    --kill)             cmd_kill "${2:-}" ;;
    --toggle-filter)    cmd_toggle_filter ;;
    --prompt)           cmd_prompt ;;
    --header)           cmd_header ;;
    --arm)              cmd_arm "${2:-}" "${3:-}" ;;
    --clear-pending)    cmd_clear_pending ;;
    --confirm-pending)  cmd_confirm_pending ;;
    --y-action)         cmd_y_action ;;
    --n-action)         cmd_n_action ;;
    --enter-action)     cmd_enter_action ;;
    "")                 cmd_picker ;;
    *)                  echo "unknown command: $1" >&2; exit 2 ;;
esac

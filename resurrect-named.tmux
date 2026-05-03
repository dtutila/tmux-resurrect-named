#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

save_key=$(tmux show-option -gqv "@resurrect-named-save-key")
restore_key=$(tmux show-option -gqv "@resurrect-named-restore-key")
[ -z "$save_key" ] && save_key="S"
[ -z "$restore_key" ] && restore_key="R"

tmux bind-key "$save_key" command-prompt -I "#S" -p "Save session as:" \
    "run-shell '$CURRENT_DIR/scripts/save_named.sh \"%%\"'"

tmux bind-key "$restore_key" run-shell "$CURRENT_DIR/scripts/restore_named.sh"

auto_split=$(tmux show-option -gqv "@resurrect-named-auto-split")
if [ "$auto_split" = "on" ]; then
    # Detach so the daemon outlives this run-shell invocation.
    ( "$CURRENT_DIR/scripts/auto_split.sh" >/dev/null 2>&1 </dev/null & )
fi

if ! command -v fzf-tmux >/dev/null 2>&1; then
    tmux display-message "resurrect-named: fzf-tmux missing — auto-install attempted on first restore"
fi

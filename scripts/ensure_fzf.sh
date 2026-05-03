#!/usr/bin/env bash
# Best-effort fzf install. Returns 0 if fzf-tmux ends up available.
# Only attempts non-interactive sudo so it never blocks waiting on a password.

if command -v fzf-tmux >/dev/null 2>&1; then
    exit 0
fi

run_install() {
    if command -v sudo >/dev/null 2>&1; then
        sudo -n "$@" >/dev/null 2>&1
    else
        "$@" >/dev/null 2>&1
    fi
}

if command -v pacman >/dev/null 2>&1; then
    run_install pacman -S --noconfirm fzf
elif command -v apt-get >/dev/null 2>&1; then
    run_install apt-get install -y fzf
elif command -v dnf >/dev/null 2>&1; then
    run_install dnf install -y fzf
elif command -v zypper >/dev/null 2>&1; then
    run_install zypper install -y fzf
elif command -v brew >/dev/null 2>&1; then
    brew install fzf >/dev/null 2>&1
fi

command -v fzf-tmux >/dev/null 2>&1

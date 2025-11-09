#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/utils.sh"

# Generate session name based on current directory
current_dir=$(tmux display-message -p '#{pane_current_path}')
FLOAX_SESSION_NAME=$(generate_session_name "$current_dir")
current_session=$(tmux display-message -p '#{session_name}')

tmux setenv -g ORIGIN_SESSION "$current_session"

# Check if we're currently in a floax session (any floax session, not just this directory's)
if [[ "$current_session" == floax-* ]]; then
    unset_bindings

    if [ -z "$FLOAX_TITLE" ]; then
        FLOAX_TITLE="$DEFAULT_TITLE"
    fi

    change_popup_title "$FLOAX_TITLE"
    tmux setenv -g FLOAX_TITLE "$FLOAX_TITLE"
    tmux detach-client
else
    set_bindings

    # Check if the session for this directory exists
    if tmux has-session -t "$FLOAX_SESSION_NAME" 2>/dev/null; then
        tmux_popup
    else
        # Create a new session for this directory
        tmux new-session -d -c "$current_dir" -s "$FLOAX_SESSION_NAME"
        tmux set-option -t "$FLOAX_SESSION_NAME" status off
        tmux_popup
    fi
fi

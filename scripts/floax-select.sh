#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/utils.sh"

# Get the flag passed to this script (-l or -a)
flag="$1"

# Temp file to store selection
TEMP_FILE="/tmp/floax-selection-$$"

# Run floax.sh with --print-only in a display-popup to get the selection
tmux display-popup -E -w 80% -h 80% \
    "bash -c '$CURRENT_DIR/floax.sh $flag --print-only > $TEMP_FILE'"

# Read the selection
if [ -f "$TEMP_FILE" ]; then
    selection=$(cat "$TEMP_FILE")
    rm -f "$TEMP_FILE"

    if [ -n "$selection" ]; then
        # Parse session:window
        session_name=$(echo "$selection" | cut -d':' -f1)
        window_index=$(echo "$selection" | cut -d':' -f2)

        # Check if session exists, create if not
        if ! tmux has-session -t "$session_name" 2>/dev/null; then
            current_dir=$(tmux display-message -p '#{pane_current_path}')
            tmux new-session -d -c "$current_dir" -s "$session_name"
            tmux set-option -t "$session_name" status off
        fi

        # Check if window exists, create if not
        if ! tmux list-windows -t "$session_name" -F "#{window_index}" | grep -q "^${window_index}$"; then
            current_dir=$(tmux display-message -p '#{pane_current_path}')
            tmux new-window -t "$session_name:$window_index" -c "$current_dir"
        fi

        # Set bindings and open popup
        set_bindings
        tmux_popup "$session_name" "$window_index"
    fi
fi

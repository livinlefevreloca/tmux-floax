#!/usr/bin/env bash

# Debug log file
DEBUG_LOG="/tmp/floax-select-debug.log"
echo "=== FLOAX-SELECT DEBUG $(date) ===" >> "$DEBUG_LOG"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "CURRENT_DIR: $CURRENT_DIR" >> "$DEBUG_LOG"

source "$CURRENT_DIR/utils.sh"

# Get the flag passed to this script (-l or -a)
flag="$1"
echo "Flag: $flag" >> "$DEBUG_LOG"

# Temp file to store selection
TEMP_FILE="/tmp/floax-selection-$$"
echo "TEMP_FILE: $TEMP_FILE" >> "$DEBUG_LOG"

# Test if floax.sh exists and is executable
if [ -x "$CURRENT_DIR/floax.sh" ]; then
    echo "floax.sh is executable" >> "$DEBUG_LOG"
else
    echo "ERROR: floax.sh not found or not executable at $CURRENT_DIR/floax.sh" >> "$DEBUG_LOG"
fi

# Run floax.sh with --print-only in a display-popup to get the selection
echo "Running: tmux display-popup -E -w 80% -h 80% \"bash -c '$CURRENT_DIR/floax.sh $flag --print-only > $TEMP_FILE 2>> $DEBUG_LOG'\"" >> "$DEBUG_LOG"
tmux display-popup -E -w 80% -h 80% \
    "bash -c '$CURRENT_DIR/floax.sh $flag --print-only > $TEMP_FILE 2>> $DEBUG_LOG'"
popup_exit=$?
echo "Popup exit code: $popup_exit" >> "$DEBUG_LOG"

# Read the selection
echo "Checking for temp file..." >> "$DEBUG_LOG"
if [ -f "$TEMP_FILE" ]; then
    echo "Temp file exists" >> "$DEBUG_LOG"
    selection=$(cat "$TEMP_FILE")
    echo "Selection: [$selection]" >> "$DEBUG_LOG"
    rm -f "$TEMP_FILE"

    if [ -n "$selection" ]; then
        echo "Selection is not empty, parsing..." >> "$DEBUG_LOG"
        # Parse session:window
        session_name=$(echo "$selection" | cut -d':' -f1)
        window_index=$(echo "$selection" | cut -d':' -f2)
        echo "Parsed session_name: $session_name, window_index: $window_index" >> "$DEBUG_LOG"

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
        echo "Opening floax popup for $session_name:$window_index" >> "$DEBUG_LOG"
        set_bindings
        tmux_popup "$session_name" "$window_index"
    else
        echo "Selection is empty, user may have cancelled" >> "$DEBUG_LOG"
    fi
else
    echo "ERROR: Temp file not found at $TEMP_FILE" >> "$DEBUG_LOG"
fi

echo "=== END DEBUG ===" >> "$DEBUG_LOG"

#!/usr/bin/env bash

# Use existing debug log file
DEBUG_FILE="/tmp/floax-debug.log"

# Log IMMEDIATELY to verify script is being called
echo "[$(date '+%H:%M:%S')] === FLOAX-SELECT START ===" >> "$DEBUG_FILE" 2>&1
echo "[$(date '+%H:%M:%S')] Script args: $@" >> "$DEBUG_FILE" 2>&1
echo "[$(date '+%H:%M:%S')] PWD: $PWD" >> "$DEBUG_FILE" 2>&1

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[$(date '+%H:%M:%S')] CURRENT_DIR: $CURRENT_DIR" >> "$DEBUG_FILE"

source "$CURRENT_DIR/utils.sh"

# Get the flag passed to this script (-l or -a)
flag="$1"
echo "[$(date '+%H:%M:%S')] Flag: $flag" >> "$DEBUG_FILE"

# Temp file to store selection
TEMP_FILE="/tmp/floax-selection-$$"
echo "[$(date '+%H:%M:%S')] TEMP_FILE: $TEMP_FILE" >> "$DEBUG_FILE"

# Test if floax.sh exists and is executable
if [ -x "$CURRENT_DIR/floax.sh" ]; then
    echo "[$(date '+%H:%M:%S')] floax.sh is executable" >> "$DEBUG_FILE"
else
    echo "[$(date '+%H:%M:%S')] ERROR: floax.sh not found or not executable at $CURRENT_DIR/floax.sh" >> "$DEBUG_FILE"
fi

# Run floax.sh with --print-only in a display-popup to get the selection
echo "[$(date '+%H:%M:%S')] Running display-popup with: $CURRENT_DIR/floax.sh $flag --print-only" >> "$DEBUG_FILE"
tmux display-popup -E -w 80% -h 80% \
    "bash -c \"$CURRENT_DIR/floax.sh $flag --print-only > $TEMP_FILE 2>> $DEBUG_FILE\""
popup_exit=$?
echo "[$(date '+%H:%M:%S')] Popup exit code: $popup_exit" >> "$DEBUG_FILE"

# Read the selection
echo "[$(date '+%H:%M:%S')] Checking for temp file..." >> "$DEBUG_FILE"
if [ -f "$TEMP_FILE" ]; then
    echo "[$(date '+%H:%M:%S')] Temp file exists" >> "$DEBUG_FILE"
    selection=$(cat "$TEMP_FILE")
    echo "[$(date '+%H:%M:%S')] Selection: [$selection]" >> "$DEBUG_FILE"
    rm -f "$TEMP_FILE"

    if [ -n "$selection" ]; then
        echo "[$(date '+%H:%M:%S')] Selection is not empty, parsing..." >> "$DEBUG_FILE"
        # Parse session:window
        session_name=$(echo "$selection" | cut -d':' -f1)
        window_index=$(echo "$selection" | cut -d':' -f2)
        echo "[$(date '+%H:%M:%S')] Parsed session_name: $session_name, window_index: $window_index" >> "$DEBUG_FILE"

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
        echo "[$(date '+%H:%M:%S')] Opening floax popup for $session_name:$window_index" >> "$DEBUG_FILE"
        set_bindings
        tmux_popup "$session_name" "$window_index"
    else
        echo "[$(date '+%H:%M:%S')] Selection is empty, user may have cancelled" >> "$DEBUG_FILE"
    fi
else
    echo "[$(date '+%H:%M:%S')] ERROR: Temp file not found at $TEMP_FILE" >> "$DEBUG_FILE"
fi

echo "[$(date '+%H:%M:%S')] === FLOAX-SELECT END ===" >> "$DEBUG_FILE"

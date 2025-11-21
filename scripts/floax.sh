#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/utils.sh"

# Display help menu
show_help() {
    cat << EOF
FloaX - Floating tmux session manager

USAGE:
    floax.sh [OPTIONS] [COMMAND]

OPTIONS:
    -h, --help          Show this help message
    -d, --debug         Enable debug output
    -s, --session NAME  Attach to or create a specific named session
    -n, --new           Force create a new window in the session
    -l, --list          List windows in directory session with fzf preview and select one
    -a, --all           List ALL windows across all tmux sessions with fzf preview and select one
    -r, --replace       Kill the existing session for this directory/name and create fresh

COMMAND:
    Any command after the options will be executed in the floax session.
    If no command is provided, opens a shell.

EXAMPLES:
    # Open default floax session for current directory
    floax.sh

    # Open with a command
    floax.sh lazygit

    # Create a new window in the session
    floax.sh -n

    # Attach to a named session
    floax.sh -s myproject

    # Replace session for current directory
    floax.sh -r

    # List windows and choose
    floax.sh -l

    # List ALL tmux sessions and choose
    floax.sh -a

    # Named session with command
    floax.sh -s work npm test

    # Replace and run command
    floax.sh -r lazygit

    # Enable debug output
    floax.sh -d

BEHAVIOR:
    - Without options: Reuses existing directory session or creates new
    - Multiple windows: Use -l to show fzf menu with live preview (requires fzf)
    - Session naming: Based on last 2 directory components (e.g., floax-my-project)
    - Windows: -n flag creates new windows within the same session
    - Window selection: Uses tmux's last active window by default

EOF
    exit 0
}

# Debug logging function
DEBUG=false
DEBUG_FILE="/tmp/floax-debug.log"
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo "[$(date '+%H:%M:%S')] $@" >> "$DEBUG_FILE"
    fi
}

# Always log keybinding invocations to help debug toggle issues
echo "[$(date '+%H:%M:%S')] === FLOAX INVOKED ===" >> "$DEBUG_FILE"
echo "[$(date '+%H:%M:%S')] Args: $*" >> "$DEBUG_FILE"
echo "[$(date '+%H:%M:%S')] Arg count: $#" >> "$DEBUG_FILE"

# Parse arguments
custom_session=""
command=""
force_new=false
list_all=false
list_dir=false
replace=false
print_only=false

echo "[$(date '+%H:%M:%S')] Starting argument parsing" >> "$DEBUG_FILE"
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -s|--session)
            custom_session="$2"
            shift 2
            ;;
        -n|--new)
            force_new=true
            shift
            ;;
        -l|--list)
            list_dir=true
            shift
            ;;
        -a|--all)
            list_all=true
            shift
            ;;
        -r|--replace)
            replace=true
            shift
            ;;
        --print-only)
            print_only=true
            shift
            ;;
        *)
            # Everything else is treated as a command
            command="$*"
            break
            ;;
    esac
done

echo "[$(date '+%H:%M:%S')] Finished argument parsing" >> "$DEBUG_FILE"
echo "[$(date '+%H:%M:%S')] command='$command' custom_session='$custom_session' force_new=$force_new list_all=$list_all list_dir=$list_dir replace=$replace" >> "$DEBUG_FILE"

# Find all windows in a session
find_session_windows() {
    local session_name="$1"
    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux list-windows -t "$session_name" -F "#{window_index}" 2>/dev/null || true
    fi
}

# Find next available window index
find_next_window_index() {
    local session_name="$1"
    if ! tmux has-session -t "$session_name" 2>/dev/null; then
        echo "0"
        return
    fi

    local windows=$(find_session_windows "$session_name")
    local max_index=-1

    while IFS= read -r index; do
        if [ -n "$index" ] && [ "$index" -gt "$max_index" ]; then
            max_index="$index"
        fi
    done <<< "$windows"

    echo $((max_index + 1))
}

# Check FIRST if we're already in a floax session - if so, just detach
current_session=$(tmux display-message -p '#{session_name}')
echo "[$(date '+%H:%M:%S')] Current session: $current_session" >> "$DEBUG_FILE"

# If we're in ANY floax session, just toggle off (detach)
if [[ "$current_session" == floax-* ]]; then
    echo "[$(date '+%H:%M:%S')] Already inside floax session - toggling off immediately" >> "$DEBUG_FILE"
    unset_bindings

    if [ -z "$FLOAX_TITLE" ]; then
        FLOAX_TITLE="$DEFAULT_TITLE"
    fi

    echo "[$(date '+%H:%M:%S')] Calling change_popup_title" >> "$DEBUG_FILE"
    if type change_popup_title >/dev/null 2>&1; then
        change_popup_title "$FLOAX_TITLE"
        echo "[$(date '+%H:%M:%S')] change_popup_title succeeded" >> "$DEBUG_FILE"
    else
        echo "[$(date '+%H:%M:%S')] WARNING: change_popup_title function not found, skipping" >> "$DEBUG_FILE"
    fi
    tmux setenv -g FLOAX_TITLE "$FLOAX_TITLE"
    tmux setenv -g ORIGIN_SESSION "$current_session"
    echo "[$(date '+%H:%M:%S')] About to detach client" >> "$DEBUG_FILE"
    tmux detach-client
    echo "[$(date '+%H:%M:%S')] Detached successfully" >> "$DEBUG_FILE"
    exit 0
fi

# Not in a floax session, so proceed with session determination
echo "[$(date '+%H:%M:%S')] Not in floax session, proceeding with session determination" >> "$DEBUG_FILE"

# Generate session name based on current directory or use custom session
echo "[$(date '+%H:%M:%S')] Getting current directory" >> "$DEBUG_FILE"
current_dir=$(tmux display-message -p '#{pane_current_path}')
echo "[$(date '+%H:%M:%S')] current_dir='$current_dir'" >> "$DEBUG_FILE"

# Handle replace flag - kill the existing session for this directory/name and create a new one
if [ "$replace" = true ]; then
    if [ -n "$custom_session" ]; then
        base_session_name="$custom_session"
    else
        base_session_name=$(generate_session_name "$current_dir")
    fi

    # Kill the session if it exists
    if tmux has-session -t "$base_session_name" 2>/dev/null; then
        tmux kill-session -t "$base_session_name"
    fi

    # Set the session name to the base name
    FLOAX_SESSION_NAME="$base_session_name"
    FLOAX_WINDOW_INDEX="0"
fi

# Determine final session name
echo "[$(date '+%H:%M:%S')] Determining final session name" >> "$DEBUG_FILE"
if [ "$replace" = true ]; then
    echo "[$(date '+%H:%M:%S')] Replace is true, FLOAX_SESSION_NAME already set" >> "$DEBUG_FILE"
    # Already handled above, FLOAX_SESSION_NAME is set
    :
elif [ "$list_all" = true ]; then
    echo "[$(date '+%H:%M:%S')] List all is true" >> "$DEBUG_FILE"
    # List all windows across all tmux sessions
    all_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)

    # Filter out the current session to avoid recursion
    echo "[$(date '+%H:%M:%S')] Filtering out current session: $current_session" >> "$DEBUG_FILE"
    all_sessions=$(echo "$all_sessions" | grep -v "^${current_session}$" || true)

    if [ -z "$all_sessions" ]; then
        # No sessions exist (or only current session), create a new one based on directory
        FLOAX_SESSION_NAME=$(generate_session_name "$current_dir")
        FLOAX_WINDOW_INDEX="0"
    else
        # Build a list of all windows across all sessions
        # Format: "session_name window_index [window_index] window_name"
        all_windows=""
        while IFS= read -r session; do
            windows=$(tmux list-windows -t "$session" -F "#{window_index} [#{window_index}] #{window_name}" 2>/dev/null)
            while IFS= read -r window; do
                all_windows="${all_windows}${session} ${window}"$'\n'
            done <<< "$windows"
        done <<< "$all_sessions"

        if command -v fzf >/dev/null 2>&1; then
            selected=$(echo "$all_windows" | fzf \
                --prompt="Select session:window: " \
                --height=80% \
                --reverse \
                --preview="tmux capture-pane -ep -t {1}:{2}" \
                --preview-window=right:60%)
            if [ -z "$selected" ]; then
                # User cancelled fzf, exit
                exit 0
            fi
            # Parse the selection: "session window_index [window_index] window_name"
            FLOAX_SESSION_NAME=$(echo "$selected" | awk '{print $1}')
            FLOAX_WINDOW_INDEX=$(echo "$selected" | awk '{print $2}')
        else
            # fzf not available, just use the first window of the first session
            FLOAX_SESSION_NAME=$(echo "$all_sessions" | head -n 1)
            FLOAX_WINDOW_INDEX="0"
        fi
    fi
elif [ -n "$custom_session" ]; then
    echo "[$(date '+%H:%M:%S')] Custom session specified: $custom_session" >> "$DEBUG_FILE"
    FLOAX_SESSION_NAME="$custom_session"

    if [ "$force_new" = true ]; then
        echo "[$(date '+%H:%M:%S')] Force new with custom session - creating new window" >> "$DEBUG_FILE"
        # Force create a new window in the session
        FLOAX_WINDOW_INDEX=$(find_next_window_index "$FLOAX_SESSION_NAME")
    else
        # Check if session exists
        if tmux has-session -t "$FLOAX_SESSION_NAME" 2>/dev/null; then
            # Session exists, use tmux's last active window
            echo "[$(date '+%H:%M:%S')] Session exists, using last active window (@)" >> "$DEBUG_FILE"
            FLOAX_WINDOW_INDEX="@"
        else
            # Session doesn't exist yet, will create at window 0
            echo "[$(date '+%H:%M:%S')] Session doesn't exist, will create at window 0" >> "$DEBUG_FILE"
            FLOAX_WINDOW_INDEX="0"
        fi
    fi
else
    echo "[$(date '+%H:%M:%S')] No custom session, generating from directory" >> "$DEBUG_FILE"
    debug_log "Calling generate_session_name with: $current_dir"
    FLOAX_SESSION_NAME=$(generate_session_name "$current_dir")
    echo "[$(date '+%H:%M:%S')] FLOAX_SESSION_NAME: $FLOAX_SESSION_NAME" >> "$DEBUG_FILE"
    debug_log "FLOAX_SESSION_NAME: $FLOAX_SESSION_NAME"

    if [ "$force_new" = true ]; then
        echo "[$(date '+%H:%M:%S')] Force new is true - creating new window" >> "$DEBUG_FILE"
        # Force create a new window in the session
        FLOAX_WINDOW_INDEX=$(find_next_window_index "$FLOAX_SESSION_NAME")
    else
        echo "[$(date '+%H:%M:%S')] Force new is false, checking for existing session" >> "$DEBUG_FILE"

        if tmux has-session -t "$FLOAX_SESSION_NAME" 2>/dev/null; then
            debug_log "Session exists, checking windows"
            # Session exists - check if we should list windows
            if [ "$list_dir" = true ]; then
                # -l flag: show fzf with windows
                echo "[$(date '+%H:%M:%S')] List dir flag set, showing fzf for windows" >> "$DEBUG_FILE"
                windows=$(tmux list-windows -t "$FLOAX_SESSION_NAME" -F "#{window_index}: #{window_name}" 2>/dev/null)

                if command -v fzf >/dev/null 2>&1; then
                    selected=$(echo "$windows" | fzf \
                        --prompt="Select window: " \
                        --height=80% \
                        --reverse \
                        --delimiter=':' \
                        --preview="tmux capture-pane -ep -t ${FLOAX_SESSION_NAME}:{1}" \
                        --preview-window=right:60%)
                    if [ -z "$selected" ]; then
                        echo "[$(date '+%H:%M:%S')] User cancelled fzf, exiting" >> "$DEBUG_FILE"
                        exit 0
                    fi
                    # Extract window index (everything before the colon)
                    FLOAX_WINDOW_INDEX=$(echo "$selected" | cut -d':' -f1 | tr -d ' ')
                else
                    echo "[$(date '+%H:%M:%S')] fzf not available, using window 0" >> "$DEBUG_FILE"
                    FLOAX_WINDOW_INDEX="0"
                fi
            else
                # Default: attach to tmux's last active window (session exists)
                echo "[$(date '+%H:%M:%S')] Using last active window (@)" >> "$DEBUG_FILE"
                debug_log "Using last active window"
                FLOAX_WINDOW_INDEX="@"
            fi
        else
            debug_log "No existing session, will create at window 0"
            # No existing session, will create at window 0
            FLOAX_WINDOW_INDEX="0"
        fi
        echo "[$(date '+%H:%M:%S')] Final FLOAX_WINDOW_INDEX: $FLOAX_WINDOW_INDEX" >> "$DEBUG_FILE"
        debug_log "Final FLOAX_WINDOW_INDEX: $FLOAX_WINDOW_INDEX"
    fi
fi

echo "[$(date '+%H:%M:%S')] Session name determination complete" >> "$DEBUG_FILE"

debug_log "=== SESSION NAME DETERMINATION COMPLETE ==="
debug_log "Final FLOAX_SESSION_NAME: [$FLOAX_SESSION_NAME]"
debug_log "Final FLOAX_WINDOW_INDEX: [$FLOAX_WINDOW_INDEX]"

echo "[$(date '+%H:%M:%S')] Target FLOAX_SESSION_NAME: $FLOAX_SESSION_NAME" >> "$DEBUG_FILE"
echo "[$(date '+%H:%M:%S')] Target FLOAX_WINDOW_INDEX: $FLOAX_WINDOW_INDEX" >> "$DEBUG_FILE"
debug_log "Target FLOAX_SESSION_NAME: $FLOAX_SESSION_NAME"
debug_log "Target FLOAX_WINDOW_INDEX: $FLOAX_WINDOW_INDEX"

# If print-only mode, just output the session:window and exit
if [ "$print_only" = true ]; then
    echo "${FLOAX_SESSION_NAME}:${FLOAX_WINDOW_INDEX}"
    exit 0
fi

tmux setenv -g ORIGIN_SESSION "$current_session"

# We're not in a floax session (checked earlier), so proceed with toggling on
echo "[$(date '+%H:%M:%S')] Toggling floax on" >> "$DEBUG_FILE"
debug_log "Not in a floax session, proceeding..."
set_bindings

# Check if the session exists
debug_log "Checking if session $FLOAX_SESSION_NAME exists..."
if tmux has-session -t "$FLOAX_SESSION_NAME" 2>/dev/null; then
    debug_log "Session EXISTS"

    # If using @ (last active window), skip window creation logic
    if [ "$FLOAX_WINDOW_INDEX" = "@" ]; then
        debug_log "Using last active window (@), skipping window checks"
        # If command provided, send it to the active window
        if [ -n "$command" ]; then
            tmux send-keys -t "$FLOAX_SESSION_NAME:@" "$command" Enter
        fi
    else
        # Session exists - check if we need to create a new window
        if ! tmux list-windows -t "$FLOAX_SESSION_NAME" -F "#{window_index}" | grep -q "^${FLOAX_WINDOW_INDEX}$"; then
            debug_log "Window $FLOAX_WINDOW_INDEX does not exist, creating new window"
            if [ -n "$command" ]; then
                tmux new-window -t "$FLOAX_SESSION_NAME:$FLOAX_WINDOW_INDEX" -c "$current_dir" "$command"
            else
                tmux new-window -t "$FLOAX_SESSION_NAME:$FLOAX_WINDOW_INDEX" -c "$current_dir"
            fi
        else
            debug_log "Window $FLOAX_WINDOW_INDEX exists"
            # Window exists - if command provided, send it to the window
            if [ -n "$command" ]; then
                tmux send-keys -t "$FLOAX_SESSION_NAME:$FLOAX_WINDOW_INDEX" "$command" Enter
            fi
        fi
    fi
    tmux_popup "$FLOAX_SESSION_NAME" "$FLOAX_WINDOW_INDEX"
else
    debug_log "Session DOES NOT EXIST, creating..."
    # Create a new session for this directory
    debug_log "Creating new session: $FLOAX_SESSION_NAME in directory: $current_dir"
    if [ -n "$command" ]; then
        # Create session and run the command
        tmux new-session -d -c "$current_dir" -s "$FLOAX_SESSION_NAME" "$command"
    else
        # Create session with default shell
        tmux new-session -d -c "$current_dir" -s "$FLOAX_SESSION_NAME"
    fi
    debug_log "Session creation result: $?"
    tmux set-option -t "$FLOAX_SESSION_NAME" status off
    debug_log "Calling tmux_popup with session: $FLOAX_SESSION_NAME, window: $FLOAX_WINDOW_INDEX"
    tmux_popup "$FLOAX_SESSION_NAME" "$FLOAX_WINDOW_INDEX"
fi

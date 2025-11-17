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
    -n, --new           Force create a new numbered session (e.g., session-1, session-2)
    -a, --all           List all tmux sessions with fzf preview and select one
    -r, --replace       Kill all existing sessions for this directory/name and create fresh

COMMAND:
    Any command after the options will be executed in the floax session.
    If no command is provided, opens a shell.

EXAMPLES:
    # Open default floax session for current directory
    floax.sh

    # Open with a command
    floax.sh lazygit

    # Create a new numbered session
    floax.sh -n

    # Attach to a named session
    floax.sh -s myproject

    # Replace all sessions for current directory
    floax.sh -r

    # List all sessions and choose
    floax.sh -a

    # Named session with command
    floax.sh -s work npm test

    # Replace and run command
    floax.sh -r lazygit

    # Enable debug output
    floax.sh -d

BEHAVIOR:
    - Without options: Reuses existing directory session or creates new
    - Multiple sessions: Shows fzf menu with live preview (requires fzf)
    - Session naming: Based on last 2 directory components (e.g., floax-my-project)
    - Numbering: First session has no number, subsequent ones get -1, -2, etc.

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
replace=false

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
        -a|--all)
            list_all=true
            shift
            ;;
        -r|--replace)
            replace=true
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
echo "[$(date '+%H:%M:%S')] command='$command' custom_session='$custom_session' force_new=$force_new list_all=$list_all replace=$replace" >> "$DEBUG_FILE"

# Find all existing floax sessions for a base session name
find_matching_sessions() {
    local base_name="$1"
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${base_name}\(-[0-9]\+\)\?$" || true
}

# Find next available session number
find_next_session_number() {
    local base_name="$1"
    local sessions=$(find_matching_sessions "$base_name")
    local max_num=-1

    while IFS= read -r session; do
        if [[ "$session" == "$base_name" ]]; then
            max_num=0
        elif [[ "$session" =~ ^${base_name}-([0-9]+)$ ]]; then
            local num="${BASH_REMATCH[1]}"
            if [ "$num" -gt "$max_num" ]; then
                max_num="$num"
            fi
        fi
    done <<< "$sessions"

    echo $((max_num + 1))
}

# Generate session name based on current directory or use custom session
echo "[$(date '+%H:%M:%S')] Getting current directory" >> "$DEBUG_FILE"
current_dir=$(tmux display-message -p '#{pane_current_path}')
echo "[$(date '+%H:%M:%S')] current_dir='$current_dir'" >> "$DEBUG_FILE"

# Handle replace flag - kill all existing sessions for this directory/name and create a new one
if [ "$replace" = true ]; then
    if [ -n "$custom_session" ]; then
        base_session_name="$custom_session"
    else
        base_session_name=$(generate_session_name "$current_dir")
    fi

    # Find and kill all matching sessions
    matching_sessions=$(find_matching_sessions "$base_session_name")
    if [ -n "$matching_sessions" ]; then
        while IFS= read -r session; do
            if tmux has-session -t "$session" 2>/dev/null; then
                tmux kill-session -t "$session"
            fi
        done <<< "$matching_sessions"
    fi

    # Set the session name to the base name (no number)
    FLOAX_SESSION_NAME="$base_session_name"
fi

# Determine final session name
if [ "$replace" = true ]; then
    # Already handled above, FLOAX_SESSION_NAME is set
    :
elif [ "$list_all" = true ]; then
    # List all tmux sessions and let user choose
    all_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)

    if [ -z "$all_sessions" ]; then
        # No sessions exist, create a new one based on directory
        FLOAX_SESSION_NAME=$(generate_session_name "$current_dir")
    else
        if command -v fzf >/dev/null 2>&1; then
            FLOAX_SESSION_NAME=$(echo "$all_sessions" | fzf \
                --prompt="Select session: " \
                --height=80% \
                --reverse \
                --preview="tmux capture-pane -ep -t {}" \
                --preview-window=right:60%)
            if [ -z "$FLOAX_SESSION_NAME" ]; then
                # User cancelled fzf, exit
                exit 0
            fi
        else
            # fzf not available, just use the first one
            FLOAX_SESSION_NAME=$(echo "$all_sessions" | head -n 1)
        fi
    fi
elif [ -n "$custom_session" ]; then
    base_session_name="$custom_session"

    if [ "$force_new" = true ]; then
        # Force create a new numbered session
        next_num=$(find_next_session_number "$base_session_name")
        if [ "$next_num" -eq 0 ]; then
            FLOAX_SESSION_NAME="$base_session_name"
        else
            FLOAX_SESSION_NAME="${base_session_name}-${next_num}"
        fi
    else
        FLOAX_SESSION_NAME="$base_session_name"
    fi
else
    debug_log "Calling generate_session_name with: $current_dir"
    base_session_name=$(generate_session_name "$current_dir")
    debug_log "base_session_name result: $base_session_name"

    if [ "$force_new" = true ]; then
        # Force create a new numbered session
        next_num=$(find_next_session_number "$base_session_name")
        if [ "$next_num" -eq 0 ]; then
            FLOAX_SESSION_NAME="$base_session_name"
        else
            FLOAX_SESSION_NAME="${base_session_name}-${next_num}"
        fi
    else
        # Check for existing sessions
        debug_log "Checking for existing sessions matching: $base_session_name"
        matching_sessions=$(find_matching_sessions "$base_session_name")
        debug_log "matching_sessions: [$matching_sessions]"

        # Count non-empty lines
        if [ -z "$matching_sessions" ]; then
            session_count=0
        else
            session_count=$(echo "$matching_sessions" | wc -l | tr -d ' ')
        fi
        debug_log "session_count: $session_count"

        if [ "$session_count" -eq 0 ]; then
            debug_log "No existing sessions, using base name"
            # No existing sessions, use base name
            FLOAX_SESSION_NAME="$base_session_name"
        elif [ "$session_count" -eq 1 ]; then
            debug_log "Exactly one session exists, using it"
            # Exactly one session exists, use it
            FLOAX_SESSION_NAME="$matching_sessions"
        else
            debug_log "Multiple sessions exist"
            # Multiple sessions exist, let user choose with fzf
            if command -v fzf >/dev/null 2>&1; then
                debug_log "Using fzf to select"
                FLOAX_SESSION_NAME=$(echo "$matching_sessions" | fzf \
                    --prompt="Select floax session: " \
                    --height=80% \
                    --reverse \
                    --preview="tmux capture-pane -ep -t {}" \
                    --preview-window=right:60%)
                if [ -z "$FLOAX_SESSION_NAME" ]; then
                    # User cancelled fzf, exit
                    exit 0
                fi
            else
                debug_log "fzf not available, using first session"
                # fzf not available, just use the first one
                FLOAX_SESSION_NAME=$(echo "$matching_sessions" | head -n 1)
            fi
        fi
        debug_log "Final FLOAX_SESSION_NAME after matching logic: $FLOAX_SESSION_NAME"
    fi
fi

debug_log "=== SESSION NAME DETERMINATION COMPLETE ==="
debug_log "Final FLOAX_SESSION_NAME: [$FLOAX_SESSION_NAME]"

current_session=$(tmux display-message -p '#{session_name}')

# Always log current session for debugging toggle issues
echo "[$(date '+%H:%M:%S')] Current session: $current_session" >> "$DEBUG_FILE"
echo "[$(date '+%H:%M:%S')] Target FLOAX_SESSION_NAME: $FLOAX_SESSION_NAME" >> "$DEBUG_FILE"

debug_log "Current session: $current_session"
debug_log "Target FLOAX_SESSION_NAME: $FLOAX_SESSION_NAME"

tmux setenv -g ORIGIN_SESSION "$current_session"

# Check if we're currently in a floax session (any floax session, not just this directory's)
if [[ "$current_session" == floax-* ]]; then
    echo "[$(date '+%H:%M:%S')] Inside floax session - toggling off" >> "$DEBUG_FILE"
    debug_log "Already in a floax session, detaching..."
    unset_bindings

    if [ -z "$FLOAX_TITLE" ]; then
        FLOAX_TITLE="$DEFAULT_TITLE"
    fi

    echo "[$(date '+%H:%M:%S')] Calling change_popup_title with: $FLOAX_TITLE" >> "$DEBUG_FILE"
    if type change_popup_title >/dev/null 2>&1; then
        change_popup_title "$FLOAX_TITLE"
        echo "[$(date '+%H:%M:%S')] change_popup_title succeeded" >> "$DEBUG_FILE"
    else
        echo "[$(date '+%H:%M:%S')] WARNING: change_popup_title function not found, skipping" >> "$DEBUG_FILE"
    fi
    tmux setenv -g FLOAX_TITLE "$FLOAX_TITLE"
    echo "[$(date '+%H:%M:%S')] About to detach client" >> "$DEBUG_FILE"
    tmux detach-client
    echo "[$(date '+%H:%M:%S')] Detached successfully" >> "$DEBUG_FILE"
else
    echo "[$(date '+%H:%M:%S')] Not in floax session - toggling on" >> "$DEBUG_FILE"
    debug_log "Not in a floax session, proceeding..."
    set_bindings

    # Check if the session exists
    debug_log "Checking if session $FLOAX_SESSION_NAME exists..."
    if tmux has-session -t "$FLOAX_SESSION_NAME" 2>/dev/null; then
        debug_log "Session EXISTS, attaching..."
        # Session exists - if command provided, send it to the session
        if [ -n "$command" ]; then
            tmux send-keys -t "$FLOAX_SESSION_NAME" "$command" Enter
        fi
        tmux_popup "$FLOAX_SESSION_NAME"
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
        debug_log "Calling tmux_popup with session: $FLOAX_SESSION_NAME"
        tmux_popup "$FLOAX_SESSION_NAME"
    fi
fi

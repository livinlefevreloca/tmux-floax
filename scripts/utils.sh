#!/usr/bin/env bash

envvar_value() {
    tmux showenv -g "$1" | cut -d '=' -f 2-
}

# Generate a session name based on the current directory
# Uses the last 2 path components, sanitized
generate_session_name() {
    local current_path="$1"
    local depth="${2:-2}"  # Default to last 2 components

    # Get last N components of the path
    local session_suffix=$(echo "$current_path" | awk -F/ -v n="$depth" '{for(i=NF-n+1;i<=NF;i++){printf "%s", $i; if(i<NF)printf "-"}}')

    # Sanitize: replace any non-alphanumeric chars with hyphens
    session_suffix=$(echo "$session_suffix" | tr -cs '[:alnum:]-' '-' | sed 's/^-//;s/-$//')

    # Return prefixed session name
    echo "floax-${session_suffix}"
}

tmux_option_or_fallback() {
	local option_value
	option_value="$(tmux show-option -gqv "$1")"
	if [ -z "$option_value" ]; then
		option_value="$2"
	fi
	echo "$option_value"
}

FLOAX_WIDTH=$(envvar_value FLOAX_WIDTH)
FLOAX_HEIGHT=$(envvar_value FLOAX_HEIGHT)
FLOAX_BORDER_COLOR=$(envvar_value FLOAX_BORDER_COLOR)
FLOAX_TEXT_COLOR=$(envvar_value FLOAX_TEXT_COLOR)
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOAX_CHANGE_PATH=$(envvar_value FLOAX_CHANGE_PATH)
FLOAX_TITLE=$(envvar_value FLOAX_TITLE)
DEFAULT_TITLE='FloaX: C-M-s 󰘕   C-M-b 󰁌   C-M-f 󰊓   C-M-r 󰑓   C-M-e 󱂬   C-M-d '
FLOAX_SESSION_NAME=$(envvar_value FLOAX_SESSION_NAME)
DEFAULT_SESSION_NAME='scratch'

set_bindings() {
    tmux bind -n C-M-s run "$CURRENT_DIR/zoom-options.sh in"
    tmux bind -n c-M-b run "$CURRENT_DIR/zoom-options.sh out"
    tmux bind -n C-M-f run "$CURRENT_DIR/zoom-options.sh full"
    tmux bind -n C-M-r run "$CURRENT_DIR/zoom-options.sh reset"
    tmux bind -n C-M-e run "$CURRENT_DIR/embed.sh embed"
    tmux bind -n C-M-d run "$CURRENT_DIR/zoom-options.sh lock" 
    tmux bind -n C-M-u run "$CURRENT_DIR/zoom-options.sh unlock"
}

unset_bindings() {
    tmux unbind -n C-M-s
    tmux unbind -n C-M-b
    tmux unbind -n C-M-f 
    tmux unbind -n C-M-r 
    tmux unbind -n C-M-e 
    tmux unbind -n C-M-d 
    tmux unbind -n C-M-u 
}

tmux_version() {
  tmux -V | cut -d ' ' -f 2
}

# Checks whether tmux version is >= 3.3
is_tmux_version_supported() {
    local version
    IFS='.' read -r -a version < <(tmux_version)

    if [ "${version[0]}" -gt 3 ]; then
        return 0
    fi

    # Minor version can be a number or alphanumeric, e.g. 3.3 vs 3.3a
    if [ "${version[0]}" -eq 3 ] && [ "${version[1]//[!0-9]}" -ge 3 ]; then
        return 0
    fi

    return 1
}

tmux_popup() {
    # Get current directory and generate session name
    current_dir=$(tmux display -p '#{pane_current_path}')
    FLOAX_SESSION_NAME=$(generate_session_name "$current_dir")

    # Store the session name globally for other functions to use
    tmux setenv -g FLOAX_SESSION_NAME "$FLOAX_SESSION_NAME"

    if is_tmux_version_supported; then
        if ! pop; then
            tmux setenv -g FLOAX_WIDTH "$(tmux_option_or_fallback '@floax-width' '80%')"
            tmux setenv -g FLOAX_HEIGHT "$(tmux_option_or_fallback '@floax-height' '80%')"
            pop
        fi
    else
        tmux display-message \
            -d 2000 \
            "FloaX requires tmux version 3.3 or newer"
    fi
}

pop() {
    FLOAX_WIDTH=$(envvar_value FLOAX_WIDTH)
    FLOAX_HEIGHT=$(envvar_value FLOAX_HEIGHT)

    FLOAX_TITLE=$(envvar_value FLOAX_TITLE)
    if [ -z "$FLOAX_TITLE" ]; then
        FLOAX_TITLE="$DEFAULT_TITLE"
    fi

    FLOAX_SESSION_NAME=$(envvar_value FLOAX_SESSION_NAME)
    if [ -z "$FLOAX_SESSION_NAME" ]; then
        FLOAX_SESSION_NAME="$DEFAULT_SESSION_NAME"
    fi

    tmux set-option -t "$FLOAX_SESSION_NAME" detach-on-destroy on
    tmux popup \
        -S fg="$FLOAX_BORDER_COLOR" \
        -s fg="$FLOAX_TEXT_COLOR" \
        -T "$FLOAX_TITLE" \
        -w "$FLOAX_WIDTH" \
        -h "$FLOAX_HEIGHT" \
        -b rounded \
        -E \
        "tmux attach-session -t \"$FLOAX_SESSION_NAME\"" 
}

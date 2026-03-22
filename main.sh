#!/bin/bash

# Application entrypoint.
#
# This launcher ensures the script runs with root privileges, resolves the
# project directory, loads the modular shell components, and starts the menu UI.

if [[ $EUID -ne 0 ]]; then
    echo "This script requires administrative privileges."
    # Relaunch the same script as root while preserving the original arguments.
    sudo "$0" "$@"
    exit $?
fi

# Resolve the repository directory so sourced modules work from any cwd.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/hardware.sh"
source "$SCRIPT_DIR/lib/runtime.sh"
source "$SCRIPT_DIR/lib/setup.sh"
source "$SCRIPT_DIR/lib/menu.sh"

# Hand off control to the interactive menu loop.
main

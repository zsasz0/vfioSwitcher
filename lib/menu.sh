#!/bin/bash

# Interactive terminal UI.
#
# This module renders the status screen, maps user choices to actions,
# and keeps the application running until the user exits.

render_menu() {
    local target_gpu=${MANUAL_GPU:-$AUTO_GPU}
    local driver status

    # Reflect the current binding for the selected GPU in the status banner.
    driver=$(get_current_driver "$target_gpu")

    if [[ "$driver" == "vfio-pci" ]]; then
        status="\e[35mPASSTHROUGH (VFIO)\e[0m"
    else
        status="\e[32mHOST (NVIDIA)\e[0m"
    fi

    clear
    echo "=========================================="
    echo "       GPU PASSTHROUGH TOGGLE v4"
    echo "=========================================="
    echo -e " STATUS: $status"
    echo " GPU ID: $target_gpu"
    echo "------------------------------------------"
    echo "1) Apply/Update Configuration (Run this first)"
    echo "2) TOGGLE MODE (Switch now)"
    echo "3) Set Manual GPU PCI ID"
    echo "4) Exit"
    echo -n "Select: "
}

handle_menu_option() {
    # Dispatches menu choices to setup, toggling, or manual GPU selection.
    case $1 in
        1) do_setup ;;
        2) run_toggle_mode ;;
        3) read -r -p "Enter ID (0000:01:00.0): " MANUAL_GPU ;;
        4) exit 0 ;;
    esac
}

run_toggle_mode() {
    local probe_status
    local probe_output
    local reply
    local toggle_status

    if [ ! -x "$SCRIPT_PATH" ]; then
        echo "Toggle runtime is not installed yet. Run setup first."
        read -r
        return
    fi

    probe_output=$(CONFIG_PATH="$RUNTIME_CONFIG_PATH" "$SCRIPT_PATH" --probe-session-state 2>&1)
    probe_status=$?

    if [ $probe_status -eq 10 ]; then
        echo "Target GPU appears to be active in the current host session."
        [ -n "$probe_output" ] && echo "$probe_output"
        read -r -p "Stop the display manager and continue? [y/N]: " reply
        case $reply in
            [Yy]|[Yy][Ee][Ss])
                : > "$FORCE_STOP_FLAG_PATH"
                ;;
            *)
                echo "Switch cancelled."
                read -r
                return
                ;;
        esac
    elif [ $probe_status -ne 0 ]; then
        echo "Toggle pre-check failed."
        [ -n "$probe_output" ] && echo "$probe_output"
        read -r
        return
    fi

    systemctl restart "$SERVICE_NAME"
    toggle_status=$?

    if [ $probe_status -eq 10 ] && [ $toggle_status -ne 0 ]; then
        rm -f "$FORCE_STOP_FLAG_PATH"
    fi
    if [ $toggle_status -ne 0 ]; then
        echo "Toggle operation failed."
    fi

    read -r
}

main() {
    local opt

    # Main application loop for the interactive menu.
    while true; do
        render_menu
        read -r opt
        handle_menu_option "$opt"
    done
}

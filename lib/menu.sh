#!/bin/bash

#this scrupt will use functions from the following files:
# lib/config.sh : used for retrieving configuration settings and environment variables.
# lib/hardware.sh : used for hardware detection and management utilities.
# lib/runtime.sh : used for core runtime functions and utility helpers.
# lib/setup.sh : used for system setup and installation procedures.

# Interactive terminal UI.
#
# This module renders the status screen, maps user choices to actions,
# and keeps the application running until the user exits.

render_menu() {
    # target_gpu: The GPU device identifier to be displayed and managed.
    local target_gpu=${MANUAL_GPU:-$AUTO_GPU}
    # driver: The kernel driver currently bound to the target_gpu.
    # status: The formatted status message for the menu banner.
    local driver status

    # Reflect the current binding for the selected GPU in the status banner.
    driver=$(get_current_driver "$target_gpu")

    case "$driver" in
        # GPU is bound to VFIO driver for passthrough.
        vfio-pci) status="\e[35mPASSTHROUGH (VFIO)\e[0m" ;;
        # No driver is currently bound to the GPU.
        none)     status="\e[33mHOST (UNKNOWN)\e[0m" ;;
        # GPU is bound to a host-side driver (e.g., nvidia, amdgpu).
        *)        status="\e[32mHOST ($driver)\e[0m" ;;
    esac

    clear
    echo "=========================================="
    echo "       GPU PASSTHROUGH TOGGLE"
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


# run_toggle_mode: Probes the system for active sessions and executes the GPU driver toggle.
run_toggle_mode() {
    # probe_status: Exit code of the GPU session state probe.
    # probe_output: Diagnostic output from the session state probe.
    # reply: User input for confirmation to stop the display manager.
    # toggle_status: Exit status of the systemd service restart.
    local probe_status probe_output reply toggle_status

    if [ ! -x "$SCRIPT_PATH" ]; then
        echo "Toggle runtime is not installed yet. Run setup first."
        sleep 2
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
                sleep 2
                return
                ;;
        esac
    elif [ $probe_status -ne 0 ]; then
        echo "Toggle pre-check failed."
        [ -n "$probe_output" ] && echo "$probe_output"
        sleep 3
        return
    fi

    systemctl restart "$SERVICE_NAME"
    toggle_status=$?

    if [ $probe_status -eq 10 ] && [ $toggle_status -ne 0 ]; then
        rm -f "$FORCE_STOP_FLAG_PATH"
    fi
    if [ $toggle_status -ne 0 ]; then
        echo "Toggle operation failed."
        sleep 3
    else
        sleep 1
    fi
}

main() {
    local opt

    # Main application loop for the interactive menu.
    while true; do
        # Display the interactive menu and current GPU status banner.
        render_menu
        # Read the user's numeric selection into the 'opt' variable.
        read -r opt
        # Dispatch the user's choice to the appropriate handler function .
        handle_menu_option "$opt"

        
        # Loop continues until the user exits.
    done
}


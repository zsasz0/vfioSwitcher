#!/bin/bash
set -e
trap 'echo "CRITICAL ERROR at line $LINENO"; exit 1' ERR

CONFIG_PATH=${CONFIG_PATH:-/etc/toggle-vfio.conf}
TOGGLE_VFIO_FORCE_SESSION_STOP=${TOGGLE_VFIO_FORCE_SESSION_STOP:-0}
FORCE_STOP_FLAG_PATH=${FORCE_STOP_FLAG_PATH:-/run/toggle-vfio-force-session-stop}

load_runtime_config() {
    if [ ! -r "$CONFIG_PATH" ]; then
        echo "Missing runtime config: $CONFIG_PATH"
        exit 1
    fi

    # Load the configured PCI IDs written by the setup step.
    # shellcheck disable=SC1090
    source "$CONFIG_PATH"

    if [ -z "$GPU_ID" ]; then
        echo "Missing GPU_ID in runtime config: $CONFIG_PATH"
        exit 1
    fi
}

detect_display_manager() {
    # Pick the first known display manager unit that exists on the system.
    systemctl list-units --type=service --all |
        grep -E 'gdm|sddm|lightdm|display-manager' |
        awk '{print $1}' |
        head -n 1 |
        sed 's/[^a-zA-Z._-]//g'
}

get_drv() {
    # Return the active kernel driver for a PCI device, or `none`.
    if [ -e "/sys/bus/pci/devices/$1/driver" ]; then
        basename "$(readlink /sys/bus/pci/devices/$1/driver)"
    else
        echo "none"
    fi
}

gpu_is_boot_vga() {
    [ -r "/sys/bus/pci/devices/$GPU_ID/boot_vga" ] &&
        [ "$(cat "/sys/bus/pci/devices/$GPU_ID/boot_vga")" = "1" ]
}

gpu_has_connected_outputs() {
    local status_file

    for status_file in /sys/bus/pci/devices/"$GPU_ID"/drm/*/status; do
        [ -r "$status_file" ] || continue
        [ "$(cat "$status_file")" = "connected" ] && return 0
    done

    return 1
}

gpu_has_open_drm_handles() {
    local drm_node dev_node

    for drm_node in /sys/bus/pci/devices/"$GPU_ID"/drm/card*; do
        [ -e "$drm_node" ] || continue

        dev_node="/dev/dri/$(basename "$drm_node")"
        [ -e "$dev_node" ] && fuser "$dev_node" >/dev/null 2>&1 && return 0

        for dev_node in /dev/dri/renderD*; do
            [ -e "$dev_node" ] || continue
            [ "$(readlink -f "/sys/class/drm/$(basename "$dev_node")/device")" = \
                "$(readlink -f "/sys/bus/pci/devices/$GPU_ID")" ] &&
                fuser "$dev_node" >/dev/null 2>&1 && return 0
        done
    done

    return 1
}

gpu_has_open_vendor_handles() {
    local current_driver dev_node

    current_driver=$(get_drv "$GPU_ID")
    if [ "$current_driver" = "nvidia" ]; then
        for dev_node in /dev/nvidia*; do
            [ -e "$dev_node" ] || continue
            fuser "$dev_node" >/dev/null 2>&1 && return 0
        done
    elif [ "$current_driver" = "amdgpu" ]; then
        if [ -e "/dev/kfd" ] && fuser "/dev/kfd" >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

gpu_is_in_use() {
    gpu_is_boot_vga && return 0
    gpu_has_connected_outputs && return 0
    gpu_has_open_drm_handles && return 0
    gpu_has_open_vendor_handles && return 0
    return 1
}

report_gpu_usage() {
    local status_file
    local drm_node
    local dev_node
    local current_driver
    local reported=0

    if gpu_is_boot_vga; then
        echo "- Target GPU is marked as boot_vga."
        reported=1
    fi

    for status_file in /sys/bus/pci/devices/"$GPU_ID"/drm/*/status; do
        [ -r "$status_file" ] || continue
        if [ "$(cat "$status_file")" = "connected" ]; then
            echo "- Display output is connected on $(basename "$(dirname "$status_file")")."
            reported=1
        fi
    done

    for drm_node in /sys/bus/pci/devices/"$GPU_ID"/drm/card*; do
        [ -e "$drm_node" ] || continue

        dev_node="/dev/dri/$(basename "$drm_node")"
        if [ -e "$dev_node" ] && fuser "$dev_node" >/dev/null 2>&1; then
            echo "- Processes using $dev_node:"
            report_processes_for_device "$dev_node"
            reported=1
        fi
    done

    for dev_node in /dev/dri/renderD*; do
        [ -e "$dev_node" ] || continue
        if [ "$(readlink -f "/sys/class/drm/$(basename "$dev_node")/device")" = \
            "$(readlink -f "/sys/bus/pci/devices/$GPU_ID")" ] &&
            fuser "$dev_node" >/dev/null 2>&1; then
            echo "- Processes using $dev_node:"
            report_processes_for_device "$dev_node"
            reported=1
        fi
    done

    current_driver=$(get_drv "$GPU_ID")
    if [ "$current_driver" = "nvidia" ]; then
        for dev_node in /dev/nvidia*; do
            [ -e "$dev_node" ] || continue
            if fuser "$dev_node" >/dev/null 2>&1; then
                echo "- Processes using $dev_node:"
                report_processes_for_device "$dev_node"
                reported=1
            fi
        done
    elif [ "$current_driver" = "amdgpu" ]; then
        if [ -e "/dev/kfd" ] && fuser "/dev/kfd" >/dev/null 2>&1; then
            echo "- Processes using /dev/kfd:"
            report_processes_for_device "/dev/kfd"
            reported=1
        fi
    fi

    if [ $reported -eq 0 ]; then
        echo "- GPU appears active, but no specific process handle was identified."
    fi
}

get_systemd_unit_for_pid() {
    local pid=$1
    local unit

    [ -r "/proc/$pid/cgroup" ] || return 1

    unit=$(grep -aoE '[^/[:space:]]+\.(service|scope)' "/proc/$pid/cgroup" | tail -n 1)
    [ -n "$unit" ] || return 1

    printf '%s\n' "$unit"
}

report_processes_for_device() {
    local dev_node=$1
    local pid
    local user
    local comm
    local cmd
    local unit

    for pid in $(fuser "$dev_node" 2>/dev/null | grep -oE '[0-9]+' | sort -u); do
        user=$(ps -p "$pid" -o user= 2>/dev/null | xargs)
        comm=$(ps -p "$pid" -o comm= 2>/dev/null | xargs)
        cmd=$(ps -p "$pid" -o args= 2>/dev/null | xargs)
        unit=$(get_systemd_unit_for_pid "$pid" 2>/dev/null || true)

        echo "  PID $pid"
        [ -n "$user" ] && echo "    user: $user"
        [ -n "$comm" ] && echo "    command: $comm"
        [ -n "$cmd" ] && echo "    args: $cmd"
        [ -n "$unit" ] && echo "    unit: $unit"
    done
}

prompt_for_session_stop() {
    local reply

    [ "$TOGGLE_VFIO_FORCE_SESSION_STOP" = "1" ] && return 0
    if [ -e "$FORCE_STOP_FLAG_PATH" ]; then
        rm -f "$FORCE_STOP_FLAG_PATH"
        return 0
    fi

    echo "Target GPU appears to be in use by the current host session."
    echo "A live move to another GPU is not reliable; the display stack must stop first."

    if [ -t 0 ] && [ -t 1 ]; then
        read -r -p "Stop the display manager and continue switching to VFIO? [y/N]: " reply
        case $reply in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
        esac
        echo "Switch cancelled."
        exit 1
    fi

    echo "Refusing to stop the display manager without confirmation."
    echo "Run from the interactive menu or set TOGGLE_VFIO_FORCE_SESSION_STOP=1."
    exit 1
}

probe_session_state() {
    local current_driver

    load_runtime_config
    current_driver=$(get_drv "$GPU_ID")

    if [ "$current_driver" = "vfio-pci" ]; then
        echo "vfio-bound"
        return 0
    fi

    if gpu_is_in_use; then
        echo "busy"
        report_gpu_usage
        return 10
    fi

    echo "idle"
    return 0
}

stop_display_manager() {
    # Stop the desktop stack before rebinding the GPU.
    echo "[1/5] Stopping Display Manager: $DM_SERVICE"
    [[ -n "$DM_SERVICE" ]] && systemctl stop "$DM_SERVICE" || true
    sleep 2
}

start_display_manager() {
    # Start the desktop stack again after the driver transition finishes.
    echo "[5/5] Restarting Display Manager..."
    [[ -n "$DM_SERVICE" ]] && systemctl start "$DM_SERVICE"
}

kill_gpu_processes() {
    # Force-release open handles that would block unbinding the GPU.
    echo "[2/5] Killing processes using GPU/Audio..."
    fuser -v -k -9 /dev/nvidia* 2>/dev/null || true
    fuser -v -k -9 /dev/kfd 2>/dev/null || true
    fuser -v -k -9 /dev/snd/* 2>/dev/null || true
    sleep 1
}

bind_devices_to_vfio() {
    local device

    # Override the selected PCI devices so the kernel probes them with vfio-pci.
    modprobe vfio-pci

    for device in "$GPU_ID" "$AUDIO_ID"; do
        if [ -n "$device" ] && [ -e "/sys/bus/pci/devices/$device" ]; then
            echo "vfio-pci" > "/sys/bus/pci/devices/$device/driver_override"
            if [ -e "/sys/bus/pci/devices/$device/driver" ]; then
                echo "$device" > "/sys/bus/pci/devices/$device/driver/unbind"
            fi
            echo "$device" > /sys/bus/pci/drivers_probe
        fi
    done
}

release_vfio_devices() {
    local device

    # Clear vfio-pci overrides and unbind the devices before host reprobe.
    for device in "$GPU_ID" "$AUDIO_ID"; do
        if [ -n "$device" ] && [ -e "/sys/bus/pci/devices/$device" ]; then
            echo "" > "/sys/bus/pci/devices/$device/driver_override"
            if [ -e "/sys/bus/pci/devices/$device/driver" ]; then
                echo "$device" > "/sys/bus/pci/devices/$device/driver/unbind"
            fi
        fi
    done
}

switch_to_vfio_with_session_stop() {
    # Host GPU -> VFIO handoff sequence when the target GPU is active.
    stop_display_manager

    kill_gpu_processes

    echo "[3/5] Unloading NVIDIA/AMD/Nouveau..."
    modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null || true
    modprobe -r amdgpu 2>/dev/null || true
    modprobe -r nouveau 2>/dev/null || true

    echo "[4/5] Binding to VFIO..."
    bind_devices_to_vfio
    start_display_manager
}

switch_to_vfio_without_session_stop() {
    echo "[1/3] Target GPU appears idle; skipping display manager stop."

    echo "[2/3] Unloading NVIDIA/AMD/Nouveau..."
    modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null || true
    modprobe -r amdgpu 2>/dev/null || true
    modprobe -r nouveau 2>/dev/null || true

    echo "[3/3] Binding to VFIO..."
    bind_devices_to_vfio
}

switch_to_vfio() {
    if gpu_is_in_use; then
        prompt_for_session_stop
        switch_to_vfio_with_session_stop
    else
        switch_to_vfio_without_session_stop
    fi
}

switch_to_host() {
    # VFIO -> host GPU handoff sequence.
    echo "[1/4] Releasing target GPU from VFIO without restarting the session."

    echo "[2/4] Clearing VFIO overrides..."
    release_vfio_devices

    echo "[3/4] Triggering PCI Bus Rescan (Waking up Laptop GPU)..."
    echo "1" > /sys/bus/pci/rescan
    sleep 1

    echo "[4/4] Loading Host drivers..."
    if grep -i "0x10de" /sys/bus/pci/devices/"$GPU_ID"/vendor >/dev/null 2>&1; then
        modprobe nvidia nvidia_modeset nvidia_uvm nvidia_drm
    elif grep -i "0x1002" /sys/bus/pci/devices/"$GPU_ID"/vendor >/dev/null 2>&1; then
        modprobe amdgpu
    fi
}

main() {
    local current_driver
    local probe_status

    if [ "$1" = "--probe-session-state" ]; then
        if probe_session_state; then
            return 0
        else
            probe_status=$?
            return "$probe_status"
        fi
    fi

    load_runtime_config

    # Use the current GPU binding to decide which direction to switch.
    DM_SERVICE=$(detect_display_manager)
    current_driver=$(get_drv "$GPU_ID")

    if [[ "$current_driver" != "vfio-pci" ]]; then
        switch_to_vfio
    else
        switch_to_host
    fi
}

if main "$@"; then
    exit 0
else
    exit_code=$?
    exit "$exit_code"
fi

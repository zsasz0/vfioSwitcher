#!/bin/bash

# Hardware discovery helpers.
#
# These functions inspect PCI devices and sysfs to find the NVIDIA GPU,
# its companion audio device, and the driver currently bound to a device.
# AUTO_GPU and AUTO_AUDIO cache the first detected values so the rest of the
# app can use them as defaults without repeating discovery on every call.

detect_primary_nvidia_gpu() {
    # Returns the PCI ID of the first NVIDIA VGA/3D controller, if present.
    lspci -Dnn | grep -E "VGA|3D" | grep -i "NVIDIA" | head -n 1 | awk '{print $1}'
}

detect_nvidia_audio() {
    # Returns the PCI ID of the first NVIDIA audio controller, if present.
    lspci -Dnn | grep -i "Audio" | grep -i "NVIDIA" | head -n 1 | awk '{print $1}'
}

get_current_driver() {
    local dev=$1
    local drv_path

    # Reports `none` when no device ID is set or no driver symlink exists.
    [ -z "$dev" ] || [ "$dev" = "None" ] && echo "none" && return

    drv_path="/sys/bus/pci/devices/$dev/driver"
    [ -L "$drv_path" ] && basename "$(readlink "$drv_path")" || echo "none"
}

# Default hardware targets used by the menu/setup flow unless manually overridden.
AUTO_GPU=${AUTO_GPU:-$(detect_primary_nvidia_gpu)}
AUTO_AUDIO=${AUTO_AUDIO:-$(detect_nvidia_audio)}

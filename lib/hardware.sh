#!/bin/bash

# Hardware discovery helpers.
#
# These functions inspect PCI devices and sysfs to find the NVIDIA GPU,
# its companion audio device, and the driver currently bound to a device.
# AUTO_GPU and AUTO_AUDIO cache the first detected values so the rest of the
# app can use them as defaults without repeating discovery on every call.

detect_primary_gpu() {
    # Returns the PCI ID of the first NVIDIA or AMD VGA/3D controller, if present.
    local dev class vendor
    for dev in /sys/bus/pci/devices/*; do
        [ -e "$dev/class" ] && read -r class < "$dev/class" 2>/dev/null || continue
        [ -e "$dev/vendor" ] && read -r vendor < "$dev/vendor" 2>/dev/null || continue
        
        # Class 0x03xxxx is Display Controller (VGA/3D)
        # Vendor 0x10de is NVIDIA, 0x1002/0x1022 are AMD
        if [[ "$class" == 0x03* ]] && [[ "$vendor" == "0x10de" || "$vendor" == "0x1002" || "$vendor" == "0x1022" ]]; then
            basename "$dev"
            return 0
        fi
    done
}

detect_primary_audio() {
    # Returns the PCI ID of the first NVIDIA or AMD audio controller, if present.
    local dev class vendor
    for dev in /sys/bus/pci/devices/*; do
        [ -e "$dev/class" ] && read -r class < "$dev/class" 2>/dev/null || continue
        [ -e "$dev/vendor" ] && read -r vendor < "$dev/vendor" 2>/dev/null || continue
        
        # Class 0x04xxxx is Multimedia Controller (Audio)
        if [[ "$class" == 0x04* ]] && [[ "$vendor" == "0x10de" || "$vendor" == "0x1002" || "$vendor" == "0x1022" ]]; then
            basename "$dev"
            return 0
        fi
    done
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
AUTO_GPU=${AUTO_GPU:-$(detect_primary_gpu)}
AUTO_AUDIO=${AUTO_AUDIO:-$(detect_primary_audio)}

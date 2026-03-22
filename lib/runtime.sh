#!/bin/bash

# Runtime installer helpers.
#
# This module installs the bundled runtime helper script and writes the small
# config file it reads to determine which PCI devices to switch.

install_runtime_script() {
    # Install the static runtime helper into its system path with execute bits.
    install -Dm755 "$RUNTIME_SOURCE_PATH" "$SCRIPT_PATH"
}

write_runtime_config() {
    local target_gpu=$1
    local target_audio=$2
    local tmp_file

    # Write the selected PCI IDs as a small environment file consumed at runtime.
    tmp_file=$(mktemp)
    printf 'GPU_ID="%s"\nAUDIO_ID="%s"\n' "$target_gpu" "$target_audio" > "$tmp_file"
    install -Dm644 "$tmp_file" "$RUNTIME_CONFIG_PATH"
    rm -f "$tmp_file"
}

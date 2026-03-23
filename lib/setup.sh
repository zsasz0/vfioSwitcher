#!/bin/bash

# Setup/install helpers.
#
# This module writes the systemd unit, installs the bundled runtime script,
# writes its device config, and reloads systemd so the menu can switch modes.

write_service_unit() {
    # Create the systemd oneshot unit that executes the installed runtime script.
    cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=Toggle VFIO/Host GPU
After=network.target

[Service]
Type=oneshot
Environment=CONFIG_PATH=$RUNTIME_CONFIG_PATH
Environment=FORCE_STOP_FLAG_PATH=$FORCE_STOP_FLAG_PATH
ExecStart=$SCRIPT_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

do_setup() {
    local target_gpu=${MANUAL_GPU:-$AUTO_GPU}
    local target_audio=${MANUAL_AUDIO:-$AUTO_AUDIO}

    # Refuse setup when no GPU target can be detected or has been provided.
    if [ -z "$target_gpu" ]; then
        echo "Error: No GPU detected."
        sleep 2
        return
    fi

    # Install the runtime script, its device config, and the companion systemd unit.
    install_runtime_script
    write_runtime_config "$target_gpu" "$target_audio"
    write_service_unit
    systemctl daemon-reload
    echo "Config applied successfully."
    sleep 2
}

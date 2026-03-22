#!/bin/bash

# Centralized paths used by the installer/setup flow.
# Each value can be overridden from the environment before launching `main.sh`.
#
# PROJECT_ROOT:
#   Repository root used to resolve bundled runtime assets.
# RUNTIME_SOURCE_PATH:
#   Static runtime script shipped with the repo and installed onto the system.
# SCRIPT_PATH:
#   Location where the installed root-owned toggle script is written.
# RUNTIME_CONFIG_PATH:
#   Environment-style config file containing the selected GPU/audio PCI IDs.
# FORCE_STOP_FLAG_PATH:
#   Ephemeral flag file used to approve stopping the display stack for a busy GPU.
# SERVICE_PATH:
#   Full path of the systemd unit created by the setup step.
# SERVICE_NAME:
#   Unit name used when restarting the toggle service from the menu.
PROJECT_ROOT=${PROJECT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
RUNTIME_SOURCE_PATH=${RUNTIME_SOURCE_PATH:-$PROJECT_ROOT/runtime/toggle-vfio-logic.sh}
SCRIPT_PATH=${SCRIPT_PATH:-/usr/local/bin/toggle-vfio-logic.sh}
RUNTIME_CONFIG_PATH=${RUNTIME_CONFIG_PATH:-/etc/toggle-vfio.conf}
FORCE_STOP_FLAG_PATH=${FORCE_STOP_FLAG_PATH:-/run/toggle-vfio-force-session-stop}
SERVICE_PATH=${SERVICE_PATH:-/etc/systemd/system/toggle-vfio.service}
SERVICE_NAME=${SERVICE_NAME:-toggle-vfio.service}

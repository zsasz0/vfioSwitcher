# vfioSwitcher

A bash script to switch between GPUs for VFIO passthrough.

> [!WARNING]
> This works only with 2 GPUs (it's ok if one of them is an iGPU).

> [!WARNING]
> This handles switching a target AMD or NVIDIA secondary GPU on your system, but it is currently only tested on an NVIDIA GPU + AMD iGPU setup.

> [!NOTE]
> The reason a systemd service is used is so the toggle script runs completely decoupled from your current desktop session (similar to running it in a separate TTY). This ensures that when the script stops your display manager session to free the GPU, the script itself isn't killed in the process and can finish execution.

## Usage

Run the script with administrative privileges:

```bash
sudo ./main.sh
```

## How It Works

The `vfioSwitcher` script automates the process of unbinding your designated GPU from its host drivers and binding it to `vfio-pci` for virtual machine passthrough, and vice versa. It works using a mix of installer scripts and a systemd unit.

### 1. Hardware Detection
When you execute the script, it scans your PCI devices via `lspci` to detect your primary target GPU (AMD or NVIDIA) and its companion audio controller automatically.

### 2. Setup Phase
Using the interactive menu, you can generate an environment configuration file (`/etc/toggle-vfio.conf`) that stores your target GPU and audio device IDs. It also creates a systemd service (`toggle-vfio.service`) and places the core toggle logic (`toggle-vfio-logic.sh`) in your `/usr/local/bin` directory.

### 3. Toggling Logic
When you request a switch, the script probes your current session state:
- **Binding to VFIO (Host -> VM):** It checks if the target GPU is actively in use by your display manager (e.g., GDM, SDDM, LightDM). If it is, the script will prompt you to stop the display manager, kill any lingering processes claiming the GPU/audio, unload the host kernel drivers (`nvidia` or `amdgpu` and related), and finally bind the PCI devices to `vfio-pci`. The display manager is then restarted (using the igpu).
- **Binding to Host (VM -> Host):** To revert the process, it clears the `vfio-pci` overrides for both devices, triggers a PCI bus rescan to wake up the GPU, and reloads the respective vendor kernel drivers (`nvidia` drivers or `amdgpu`).

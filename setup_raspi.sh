#!/usr/bin/env bash
# =============================================================================
# setup_raspi.sh – System-level prerequisites for Tele Imager on Raspberry Pi 5
# =============================================================================
# Run this script once on a freshly installed Raspberry Pi OS (Bookworm or later):
#
#   bash setup_raspi.sh
#
# What it does:
#   1. Installs system packages required by picamera2 / libcamera
#   2. Installs libturbojpeg for fast JPEG encoding
#   3. Sets up optional udev rules for USB cameras (if needed alongside Pi cameras)
#   4. Installs uv and creates a .venv with --system-site-packages
#   5. Installs Tele Imager Python dependencies into the venv
#   6. Prints instructions for enabling the Pi Camera interface
# =============================================================================

set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── check platform ────────────────────────────────────────────────────────────
ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
    warn "This script is intended for ARM-based Raspberry Pi boards (detected: $ARCH)."
    warn "Continuing anyway – some packages may not exist on this platform."
fi

# ── 1. system packages ────────────────────────────────────────────────────────
info "Updating apt package lists..."
sudo apt-get update -qq

info "Installing picamera2 / libcamera system packages..."
sudo apt-get install -y \
    python3-picamera2 \
    python3-libcamera \
    libcamera-apps \
    libcamera-dev

info "Installing libturbojpeg for fast JPEG encoding..."
sudo apt-get install -y libturbojpeg-dev

# ── 2. optional: udev rules for USB UVC cameras ───────────────────────────────
info "Adding udev rules for USB video devices (allows non-root access)..."
UDEV_RULE='SUBSYSTEM=="video4linux", KERNEL=="video[0-9]*", GROUP="video", MODE="0660"'
UDEV_FILE="/etc/udev/rules.d/99-teleimager-video.rules"

if ! grep -qF "teleimager" "$UDEV_FILE" 2>/dev/null; then
    echo "$UDEV_RULE" | sudo tee "$UDEV_FILE" > /dev/null
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    info "udev rule written to $UDEV_FILE"
else
    info "udev rule already exists in $UDEV_FILE – skipping."
fi

# Add the current user to the 'video' group so the udev rule takes effect
if ! groups "$USER" | grep -q '\bvideo\b'; then
    sudo usermod -aG video "$USER"
    warn "Added '$USER' to the 'video' group. You must log out and back in (or reboot) for this to take effect."
fi

# ── 3. Install uv ─────────────────────────────────────────────────────────────
if ! command -v uv &>/dev/null; then
    info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Make uv available in the current shell session
    export PATH="$HOME/.local/bin:$PATH"
else
    info "uv is already installed ($(uv --version))."
fi

# ── 4. Create venv and install Python dependencies ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

info "Creating virtual environment at $VENV_DIR with system-site-packages..."
# --system-site-packages lets the venv see picamera2 installed as a system package
uv venv --system-site-packages "$VENV_DIR"

info "Installing Tele Imager Python dependencies (Raspberry Pi extras)..."
if ! uv pip install --python "$VENV_DIR" -e "$SCRIPT_DIR[raspi]"; then
    error "Failed to install Python dependencies. Check the output above for details."
    error "You can retry manually: uv pip install --python $VENV_DIR -e '$SCRIPT_DIR[raspi]'"
    exit 1
fi

# ── 5. Python package installation reminder ───────────────────────────────────
echo ""
info "System packages and Python dependencies installed successfully."
echo ""
echo "========================================================================"
echo "  Next steps:"
echo "========================================================================"
echo ""
echo "  1. Enable the Pi Camera interface (if not already enabled):"
echo ""
echo "       sudo raspi-config"
echo "       # Navigate to: Interface Options → Camera → Enable"
echo "       # Then reboot."
echo ""
echo "     Alternatively, add the following lines to /boot/firmware/config.txt"
echo "     (or /boot/config.txt on older images) and reboot:"
echo ""
echo "       camera_auto_detect=1"
echo "       # or for a specific sensor, e.g. IMX708 (Camera Module 3):"
echo "       # dtoverlay=imx708"
echo ""
echo "  2. A uv virtual environment has been created at .venv."
echo "     Activate it before running any teleimager commands:"
echo ""
echo "       source .venv/bin/activate"
echo ""
echo "     To reinstall or update dependencies manually:"
echo ""
echo "       uv pip install -e \".[raspi]\""
echo ""
echo "  3. Discover your camera:"
echo ""
echo "       python -c \"from picamera2 import Picamera2; Picamera2.global_camera_info()\""
echo ""
echo "  4. Configure cam_config_raspi.yaml (adjust camera_num, image_shape, fps)."
echo ""
echo "  5. Start the image server:"
echo ""
echo "       teleimager-server --raspi"
echo "       # or"
echo "       teleimager-server --config cam_config_raspi.yaml"
echo ""
echo "  6. On the client machine, connect with:"
echo ""
echo "       teleimager-client --host <raspberry-pi-ip>"
echo ""
echo "========================================================================"

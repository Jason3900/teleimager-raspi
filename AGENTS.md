# AGENTS.md

## What this repo is

Multi-camera image streaming service for Unitree robot teleoperation. Captures from UVC/OpenCV/RealSense cameras (Jetson) or picamera2 (Raspberry Pi 5) and publishes over ZeroMQ PUB-SUB and WebRTC. Two entrypoints: `teleimager-server` and `teleimager-client`.

Source lives entirely in `src/teleimager/` — two files: `image_server.py` and `image_client.py`.

---

## Install

```bash
# Jetson / generic Linux (server + client)
pip install -e ".[server]"

# Raspberry Pi 5 (server + client)
pip install -e ".[raspi]"

# Client only
pip install -e .
```

**RPi 5 critical quirk**: `picamera2` must be installed via apt, NOT pip. The `[raspi]` extra intentionally omits it. Run `setup_raspi.sh` which installs `python3-picamera2` via apt and creates a `.venv` with `--system-site-packages` so the apt-installed picamera2 is visible. Installing picamera2 from PyPI breaks libcamera native bindings at runtime.

```bash
bash setup_raspi.sh   # RPi 5 one-time setup (apt deps, udev rules, venv)
bash setup_uvc.sh     # Jetson/generic: udev rules + video group for UVC cameras
```

---

## Run

```bash
# Server — Jetson (uses cam_config_server.yaml)
teleimager-server
teleimager-server --rs          # add RealSense support
teleimager-server --cf          # camera discovery mode: print all connected cameras

# Server — Raspberry Pi 5 (uses cam_config_raspi.yaml)
teleimager-server --raspi
teleimager-server --config cam_config_raspi.yaml   # equivalent

# Custom config
teleimager-server --config /path/to/config.yaml

# Client (any machine on same network)
teleimager-client --host <server-ip>
teleimager-client --host 192.168.4.1   # typical RPi hotspot IP
```

---

## Config files

| File | Used by |
|---|---|
| `cam_config_server.yaml` | Jetson / generic Linux (default) |
| `cam_config_raspi.yaml` | Raspberry Pi 5 (`--raspi` flag) |

Each top-level YAML key is a camera topic (e.g. `head_camera`, `left_wrist_camera`). Camera identifier priority: `physical_path > serial_number > video_id`. Set unused identifiers to `null`.

Camera types: `uvc`, `opencv`, `realsense` (Jetson); `picamera2` (RPi 5 only).

---

## WebRTC certificates

Required for WebRTC streams. Certificate lookup order:
1. Env vars `XR_TELEOP_CERT` / `XR_TELEOP_KEY`
2. `~/.config/xr_teleoperate/cert.pem` / `key.pem`
3. Repo root `cert.pem` / `key.pem`

`.gitignore` excludes `*.pem`, `*.key`, `*.csr`, `*.cnf` — certs are never committed.

Generate self-signed certs if needed (see README §1.1 step 5).

---

## Public API (client usage)

All user-callable methods are marked `# public api` in the source.

```python
from teleimager.image_client import ImageClient

client = ImageClient(host="192.168.4.1", request_bgr=True)
cam_config = client.get_cam_config()          # dict of all camera topics + config
frame = client.get_frame("head_camera")       # TeleImage(fps, jpg, bgr)
frame = client.get_head_frame()               # shortcut
frame = client.get_left_wrist_frame()         # shortcut
frame = client.get_right_wrist_frame()        # shortcut
client.close()
```

`TeleImage.bgr` is a decoded numpy BGR array (only populated when `request_bgr=True`). `TeleImage.jpg` is raw JPEG bytes.

---

## Test script

```bash
python test_save_image.py --host <server-ip> --output-dir /tmp/captures
```

Connects via ZMQ, captures one frame per enabled camera, saves as PNG. Useful for verifying the server is running and cameras are streaming.

---

## Autostart (systemd)

```bash
bash setup_autostart.sh   # interactive: detects conda env, creates systemd service
```

Manage after setup:
```bash
sudo systemctl status teleimager.service
sudo journalctl -u teleimager.service -f
sudo systemctl restart teleimager.service
sudo systemctl disable teleimager.service
```

---

## No test/lint/CI tooling

No pytest, linter, type checker, formatter, CI workflows, or pre-commit hooks are configured. There is no `make` or task runner. Verification is manual: run the server, connect a client, check frames.

---

## H264 encoding

RPi 5 auto-detects and uses `h264_v4l2m2m` (V4L2 hardware encoder). Falls back to software `libx264` if unavailable. Jetson uses `libx264` only.

---

## Python version

Requires `>=3.8,<3.13`. Conda env with Python 3.10 is the documented setup.

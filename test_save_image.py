"""
Test script: connect to an image server using ImageClient, capture the current
frame from every ZMQ-enabled camera, and save each one as a PNG file.

Usage:
    python test_save_image.py [--host HOST] [--port PORT] [--output-dir OUTPUT_DIR] [--timeout TIMEOUT]

Examples:
    # Save images from the default robot IP
    python test_save_image.py

    # Save images from a custom host and port into a specific directory
    python test_save_image.py --host 192.168.4.1 --port 60002 --output-dir /tmp/captures
"""

import argparse
import os
import time

from typing import Optional

import cv2
import numpy as np

from teleimager.image_client import ImageClient, TeleImage


def save_frame_as_png(bgr_image: np.ndarray, output_path: str) -> None:
    """Save a BGR numpy array as a PNG file."""
    success = cv2.imwrite(output_path, bgr_image)
    if not success:
        raise RuntimeError(f"cv2.imwrite failed for path: {output_path}")
    print(f"  Saved: {output_path}")


def wait_for_frame(client: ImageClient, cam_topic: str, timeout: float = 5.0) -> Optional[TeleImage]:
    """Poll get_frame() until a non-None BGR image is available or timeout expires.

    Returns:
        A TeleImage with a decoded BGR array on success, or None if the timeout expires
        before a valid frame is received.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        frame = client.get_frame(cam_topic)
        if frame.bgr is not None:
            return frame
        time.sleep(0.05)
    return None


def main():
    parser = argparse.ArgumentParser(
        description="Capture the current image from each camera and save it as a PNG file."
    )
    parser.add_argument(
        "--host",
        type=str,
        default="192.168.123.164",
        help="IP address of the image server (default: 192.168.123.164)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=60000,
        help="TCP port for camera configuration request (default: 60000)",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=".",
        help="Directory where PNG files will be saved (default: current directory)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="Seconds to wait for a valid frame from each camera (default: 5.0)",
    )
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    print(f"Connecting to image server at {args.host} …")
    client = ImageClient(host=args.host, request_port=args.port, request_bgr=True)
    cam_config = client.get_cam_config()
    print(f"Camera config received. Available cameras: {list(cam_config.keys())}\n")

    saved_count = 0
    try:
        for cam_topic, cam_cfg in cam_config.items():
            if not cam_cfg.get("enable_zmq", False):
                print(f"  Skipping '{cam_topic}' (ZMQ not enabled).")
                continue

            print(f"Capturing frame from '{cam_topic}' …")
            frame = wait_for_frame(client, cam_topic, timeout=args.timeout)

            if frame is None or frame.bgr is None:
                print(f"  WARNING: No frame received for '{cam_topic}' within {args.timeout}s. Skipping.")
                continue

            output_path = os.path.join(args.output_dir, f"{cam_topic}.png")
            save_frame_as_png(frame.bgr, output_path)
            saved_count += 1

    finally:
        client.close()

    print(f"\nDone. {saved_count} PNG file(s) saved to '{os.path.abspath(args.output_dir)}'.")


if __name__ == "__main__":
    main()

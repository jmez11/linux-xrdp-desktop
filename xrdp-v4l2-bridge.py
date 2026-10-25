#!/usr/bin/env python3
"""
xrdp-v4l2-bridge.py:
On-demand multi-camera V4L2 bridge daemon.
Dynamically bridges PipeWire camera sources (xrdp-camera-0, xrdp-camera-1, ...)
to virtual V4L2 loopback devices (/dev/video0, /dev/video1, ...) for native Linux apps (Zoom, OBS, VLC).

STREAMING IS STRICTLY ON-DEMAND:
- Streams are NOT started on RDP connection. The client webcam stays OFF.
- When an application accesses a camera (opens /dev/videoN or launches Zoom/OBS/VLC),
  the bridge dynamically starts the GStreamer pipeline, which activates the camera over RDP.
- When the application closes or stops accessing the camera, the pipeline is terminated,
  which signals xrdp-rdpecam to stop the camera stream over RDP and turns the client webcam OFF.
"""

import json
import os
import signal
import subprocess
import sys
import time

# Apps that use V4L2 video devices when active
V4L2_APP_NAMES = {
    "zoom",
    "zoom-client",
    "us.zoom.zoom",
    "obs",
    "obs64",
    "cheese",
    "vlc",
    "ffmpeg",
    "ffplay",
    "guvcview",
    "camorama",
    "qv4l2",
    "skypeforlinux",
}

# Mode from environment:
# "auto" (default): starts when a client opens /dev/videoN OR when a V4L2 app (e.g. Zoom) is running
# "clients_only": ONLY starts when an active client process has opened /dev/videoN
# "always": starts immediately whenever camera and /dev/videoN exist (legacy behavior)
BRIDGE_MODE = os.environ.get("XRDP_V4L2_MODE", "auto").strip().lower()

# Grace period in seconds to keep pipeline alive after an app closes /dev/videoN
# Prevents camera flapping during brief format renegotiation or setting changes.
IDLE_GRACE_PERIOD = 3.0

# State tracking:
# active_relays[cam_name] = {
#     "proc": subprocess.Popen,
#     "dev": str,
#     "last_needed": float,
# }
active_relays = {}


def get_pipewire_cameras():
    try:
        out = subprocess.check_output(["pw-dump"], timeout=3)
        data = json.loads(out)
    except Exception:
        return []

    cameras = []
    for obj in data:
        if not isinstance(obj, dict):
            continue
        props = obj.get("info", {}).get("props", {})
        if props.get("media.class") == "Video/Source":
            name = props.get("node.name")
            desc = props.get("node.description", name)
            if name:
                cameras.append({"name": name, "desc": desc})
    cameras.sort(key=lambda c: c["name"])
    return cameras


def is_v4l2_app_running():
    """Checks if any known standalone V4L2 video app is currently running in the session."""
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return False

    for pid_str in pids:
        try:
            with open(f"/proc/{pid_str}/comm", "r") as f:
                comm = f.read().strip().lower()
            if comm in V4L2_APP_NAMES:
                return True
        except OSError:
            continue
    return False


def is_device_in_use_by_client(dev_path, our_pids):
    """
    Checks if any process (excluding this daemon and our own gst-launch children)
    currently has dev_path open.
    """
    try:
        target_stat = os.stat(dev_path)
        target_rdev = target_stat.st_rdev
    except OSError:
        return False

    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return False

    for pid_str in pids:
        pid = int(pid_str)
        if pid in our_pids or pid == os.getpid():
            continue

        # Check process name to skip helper / streamer processes
        try:
            with open(f"/proc/{pid_str}/comm", "r") as f:
                comm = f.read().strip()
            if comm in ("gst-launch-1.0", "xrdp-v4l2-brid"):
                continue
        except OSError:
            pass

        fd_dir = f"/proc/{pid_str}/fd"
        try:
            fds = os.listdir(fd_dir)
        except (PermissionError, FileNotFoundError, OSError):
            continue

        for fd in fds:
            fd_path = f"{fd_dir}/{fd}"
            try:
                link = os.readlink(fd_path)
                if link == dev_path:
                    return True
            except OSError:
                pass

            try:
                s = os.stat(fd_path)
                if s.st_rdev == target_rdev:
                    return True
            except OSError:
                pass

    return False


def stop_pipeline(relay):
    proc = relay.get("proc")
    if proc:
        try:
            proc.terminate()
            proc.wait(timeout=1.5)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
    relay["proc"] = None


def main():
    while True:
        try:
            now = time.time()
            cameras = get_pipewire_cameras()
            current_cam_names = [c["name"] for c in cameras]

            # Collect PIDs of our running gst-launch processes
            our_pids = set()
            for relay in active_relays.values():
                proc = relay.get("proc")
                if proc and proc.poll() is None:
                    our_pids.add(proc.pid)

            v4l2_app_active = is_v4l2_app_running() if BRIDGE_MODE == "auto" else False

            # Clean up disconnected cameras
            for name in list(active_relays.keys()):
                if name not in current_cam_names:
                    stop_pipeline(active_relays.pop(name))

            # Evaluate each available camera and matching /dev/videoN node
            for idx, cam in enumerate(cameras):
                dev_path = f"/dev/video{idx}"
                if not os.path.exists(dev_path):
                    continue

                cam_name = cam["name"]
                relay = active_relays.setdefault(cam_name, {
                    "proc": None,
                    "dev": dev_path,
                    "last_needed": 0.0,
                })

                # Check if camera is currently needed by an app
                is_needed = False
                if BRIDGE_MODE == "always":
                    is_needed = True
                elif BRIDGE_MODE == "clients_only":
                    is_needed = is_device_in_use_by_client(dev_path, our_pids)
                else:  # "auto"
                    # Needed if a client has opened the device, or if a V4L2 app (e.g. Zoom) is running
                    is_needed = is_device_in_use_by_client(dev_path, our_pids) or v4l2_app_active

                if is_needed:
                    relay["last_needed"] = now

                # Verify current process state
                proc = relay.get("proc")
                if proc and proc.poll() is not None:
                    proc = None
                    relay["proc"] = None

                # Determine if pipeline should be active
                should_run = (now - relay["last_needed"] < IDLE_GRACE_PERIOD)

                if should_run and proc is None:
                    # Launch GStreamer pipeline on demand
                    cmd = [
                        "gst-launch-1.0",
                        "-q",
                        "pipewiresrc", f"target-object={cam_name}",
                        "!", "videoconvert",
                        "!", "videoscale",
                        "!", "video/x-raw,format=YUY2",
                        "!", "v4l2sink", f"device={dev_path}", "sync=false"
                    ]
                    p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    relay["proc"] = p
                    our_pids.add(p.pid)
                elif not should_run and proc is not None:
                    # Shut down pipeline when no longer needed
                    stop_pipeline(relay)

        except Exception:
            pass

        time.sleep(1.0)


if __name__ == "__main__":
    main()

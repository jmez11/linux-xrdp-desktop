#!/usr/bin/env python3
"""
xrdp-v4l2-bridge.py:
Dynamically bridges multiple PipeWire camera sources (xrdp-camera-0, xrdp-camera-1, ...)
to virtual V4L2 loopback devices (/dev/video0, /dev/video1, ...) for native Linux apps (Zoom, OBS, VLC).
Automatically starts/stops GStreamer pipelines as RDP client cameras are plugged or unplugged.
"""

import json
import os
import subprocess
import time
import sys

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

def main():
    while True:
        try:
            cameras = get_pipewire_cameras()
            current_names = [c["name"] for c in cameras]

            # Terminate pipelines for cameras that disconnected
            for name in list(active_relays.keys()):
                if name not in current_names:
                    p = active_relays.pop(name)
                    try:
                        p.terminate()
                        p.wait(timeout=1)
                    except Exception:
                        pass

            # Launch pipelines for active cameras and matching /dev/videoN device nodes
            for idx, cam in enumerate(cameras):
                dev_path = f"/dev/video{idx}"
                if not os.path.exists(dev_path):
                    continue

                cam_name = cam["name"]
                proc = active_relays.get(cam_name)

                if proc and proc.poll() is not None:
                    active_relays.pop(cam_name)
                    proc = None

                if proc is None:
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
                    active_relays[cam_name] = p

        except Exception:
            pass

        time.sleep(2)

if __name__ == "__main__":
    main()

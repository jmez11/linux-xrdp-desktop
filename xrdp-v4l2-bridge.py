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

LOG_FILE = "/tmp/xrdp-v4l2-bridge.log"
WAKE_FILE = "/tmp/.xrdp-camera-wake"


def log(msg):
    try:
        t = time.strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_FILE, "a") as f:
            f.write(f"[{t}] {msg}\n")
    except Exception:
        pass


# Apps that use V4L2 video devices when active
V4L2_APP_NAMES = {
    "zoom",
    "zoomlauncher",
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

BRIDGE_MODE = os.environ.get("XRDP_V4L2_MODE", "auto").strip().lower()
IDLE_GRACE_PERIOD = 15.0

# active_relays[dev_path] = {
#     "proc": subprocess.Popen,
#     "dev": str,
#     "cam_id": int,
#     "cam_serial": int,
#     "cam_name": str,
#     "last_needed": float,
#     "last_failure": float,
# }
active_relays = {}
wake_requested = False


def handle_sigusr1(signum, frame):
    global wake_requested
    wake_requested = True


def get_pipewire_cameras():
    """Queries pw-dump and returns only active xrdp-rdpecam camera nodes."""
    try:
        out = subprocess.check_output(["pw-dump"], timeout=3)
        data = json.loads(out)
    except Exception as e:
        log(f"pw-dump failed: {e}")
        return []

    cameras = []
    for obj in data:
        if not isinstance(obj, dict):
            continue
        props = obj.get("info", {}).get("props", {})
        if props.get("media.class") == "Video/Source":
            name = props.get("node.name", "")
            # Only match client cameras published by xrdp-rdpecam
            if not name.startswith("xrdp-camera-"):
                continue

            node_id = obj.get("id")
            serial = props.get("object.serial") or props.get("object.id") or node_id
            desc = props.get("node.description", name)
            cameras.append({
                "id": node_id,
                "serial": serial,
                "name": name,
                "desc": desc,
            })

    # Sort deterministically by numeric node id
    cameras.sort(key=lambda c: int(c["id"]) if isinstance(c["id"], (int, str)) and str(c["id"]).isdigit() else 0)
    return cameras


def is_v4l2_app_running():
    """Checks if any known standalone V4L2 video app is currently running in the session."""
    if os.path.exists(WAKE_FILE):
        return True

    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return False

    for pid_str in pids:
        try:
            with open(f"/proc/{pid_str}/comm", "r") as f:
                comm = f.read().strip().lower()
            if comm in V4L2_APP_NAMES or any(name in comm for name in ("obs", "zoom", "cheese", "vlc")):
                return True
        except OSError:
            pass

        try:
            with open(f"/proc/{pid_str}/cmdline", "r") as f:
                cmdline = f.read().replace("\0", " ").lower()
            if any(name in cmdline for name in ("obs", "zoom", "cheese", "vlc")):
                return True
        except OSError:
            pass

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
    dev = relay.get("dev", "unknown")
    cam_name = relay.get("cam_name", "unknown")
    if proc:
        log(f"Stopping pipeline for {cam_name} -> {dev} (PID {proc.pid})")
        try:
            proc.terminate()
            proc.wait(timeout=0.5)
        except Exception:
            try:
                proc.kill()
                proc.wait(timeout=0.5)
            except Exception:
                pass
    relay["proc"] = None


def main():
    global wake_requested

    if "--wake" in sys.argv or "--activate" in sys.argv:
        try:
            open(WAKE_FILE, "a").close()
        except Exception:
            pass
        subprocess.run(["pkill", "-USR1", "-f", "xrdp-v4l2-bridge.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sys.exit(0)

    try:
        signal.signal(signal.SIGUSR1, handle_sigusr1)
    except Exception:
        pass

    log(f"xrdp-v4l2-bridge started (PID {os.getpid()}, MODE={BRIDGE_MODE})")

    while True:
        try:
            now = time.time()
            wake_requested = False

            cameras = get_pipewire_cameras()
            num_cams = len(cameras)

            # Collect PIDs of running gst-launch processes
            our_pids = set()
            for relay in active_relays.values():
                proc = relay.get("proc")
                if proc and proc.poll() is None:
                    our_pids.add(proc.pid)

            v4l2_app_active = is_v4l2_app_running() if BRIDGE_MODE == "auto" else False

            # Stop pipelines on video devices that no longer have a matching camera
            active_dev_paths = [f"/dev/video{idx}" for idx in range(num_cams)]
            for dev_path in list(active_relays.keys()):
                if dev_path not in active_dev_paths:
                    stop_pipeline(active_relays.pop(dev_path))

            # Check which devices are currently open by a client application
            devs_in_use = {dev: is_device_in_use_by_client(dev, our_pids) for dev in active_dev_paths}
            any_in_use = any(devs_in_use.values())

            # First pass: stop pipelines that are no longer needed.
            # In multi-camera RDP sessions, the client device (e.g. Android/Quest Camera HAL)
            # only supports streaming one physical camera at a time. Shutting down inactive
            # pipelines immediately frees the client camera hardware and resets PipeWire state.
            for dev_path, relay in list(active_relays.items()):
                in_use = devs_in_use.get(dev_path, False)
                proc = relay.get("proc")
                if proc is not None:
                    if any_in_use and not in_use:
                        log(f"Stopping inactive pipeline for {relay.get('cam_name')} -> {dev_path} (another camera in use)")
                        stop_pipeline(relay)
                    elif not any_in_use and not v4l2_app_active and (now - relay.get("last_needed", 0.0) >= IDLE_GRACE_PERIOD):
                        log(f"Stopping idle pipeline for {relay.get('cam_name')} -> {dev_path}")
                        stop_pipeline(relay)

            # Second pass: evaluate each active camera and launch the needed pipeline
            for idx, cam in enumerate(cameras):
                dev_path = f"/dev/video{idx}"
                if not os.path.exists(dev_path):
                    continue

                # Ensure non-root read/write permissions
                try:
                    os.chmod(dev_path, 0o666)
                except Exception:
                    pass

                cam_name = cam["name"]
                cam_id = cam["id"]
                cam_serial = cam["serial"]

                relay = active_relays.setdefault(dev_path, {
                    "proc": None,
                    "dev": dev_path,
                    "cam_id": cam_id,
                    "cam_serial": cam_serial,
                    "cam_name": cam_name,
                    "last_needed": 0.0,
                    "last_failure": 0.0,
                })

                # If the camera assigned to this device changed, restart pipeline
                if relay.get("cam_id") != cam_id or relay.get("cam_name") != cam_name:
                    log(f"Camera reassigned on {dev_path}: {relay.get('cam_name')} -> {cam_name}")
                    stop_pipeline(relay)
                    relay["cam_id"] = cam_id
                    relay["cam_serial"] = cam_serial
                    relay["cam_name"] = cam_name

                in_use = devs_in_use.get(dev_path, False)

                # Determine if camera is needed
                is_needed = False
                if BRIDGE_MODE == "always":
                    is_needed = True
                elif BRIDGE_MODE == "clients_only":
                    is_needed = in_use
                else:  # "auto"
                    if any_in_use:
                        is_needed = in_use
                    elif v4l2_app_active:
                        # Only pre-warm default video0 when no specific camera is open yet
                        is_needed = (idx == 0)
                    else:
                        is_needed = False

                if is_needed:
                    relay["last_needed"] = now

                # Verify current process state
                proc = relay.get("proc")
                if proc and proc.poll() is not None:
                    exit_code = proc.poll()
                    relay["proc"] = None
                    relay["last_failure"] = now
                    log(f"Pipeline for {cam_name} -> {dev_path} exited with code {exit_code}")

                # Avoid tight crash-relaunch loops if pipeline fails
                backoff_ok = (now - relay.get("last_failure", 0.0) >= 0.5)

                if is_needed and proc is None and backoff_ok:
                    log(f"Launching pipeline: {cam_name} (id={cam_id}, serial={cam_serial}) -> {dev_path}")
                    err_log = None
                    try:
                        err_log = open(f"/tmp/gst-launch-video{idx}.log", "w")
                    except Exception:
                        err_log = subprocess.DEVNULL

                    # For single camera: standard pipewiresrc connects to default Video/Source without name lookup issues.
                    # For multiple cameras: explicitly target the PipeWire node ID via path=<cam_id>.
                    if num_cams == 1:
                        src_args = ["pipewiresrc"]
                    else:
                        src_args = ["pipewiresrc", f"path={cam_id}"]

                    cmd = [
                        "gst-launch-1.0",
                        "-q",
                    ] + src_args + [
                        "!", "videoconvert",
                        "!", "videoscale",
                        "!", "video/x-raw,format=YUY2",
                        "!", "v4l2sink", f"device={dev_path}", "sync=false"
                    ]
                    p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=err_log)
                    relay["proc"] = p
                    our_pids.add(p.pid)
                    log(f"Pipeline started with PID {p.pid}")
                elif not is_needed and proc is not None and (any_in_use or not v4l2_app_active):
                    stop_pipeline(relay)

            # Consume the wake flag once all pipelines are evaluated
            if os.path.exists(WAKE_FILE):
                try:
                    os.remove(WAKE_FILE)
                except Exception:
                    pass

        except Exception as e:
            log(f"Error in main loop: {e}")

        # Sleep up to 0.5 second, but wake immediately if SIGUSR1 arrives or wake file created
        sleep_end = time.time() + 0.5
        while time.time() < sleep_end:
            if wake_requested or os.path.exists(WAKE_FILE):
                break
            time.sleep(0.05)


if __name__ == "__main__":
    main()

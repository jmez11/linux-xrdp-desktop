# Zoom & Standalone V4L2 Webcam Guide

This guide explains how to use your redirected RDP webcam (`[MS-RDPECAM]`) with **Zoom** and other standalone Video4Linux2 (`V4L2`) applications inside the `linux-xrdp-desktop` container.

---

## 1. Quick Summary: Which Approach Should You Use?

| Approach | Setup Effort | Host Kernel Access Needed? | Performance & Features |
|---|---|---|---|
| **Approach 1: Zoom Web Client** | **Zero setup** (instant) | ❌ **No** | Full audio, video, gallery view, and screen sharing via Firefox or Edge |
| **Approach 2: Native Zoom Desktop** | **1 command on host** |  **Yes** (Docker host root) | Native Linux Zoom desktop client with virtual `/dev/video0` hardware loopback |

---

## Approach 1: Zoom Web Client (Recommended — Zero Host Setup)

Because redirected RDP cameras publish as native userspace **PipeWire** video sources inside the container, all major browsers (Firefox, Microsoft Edge, Google Chrome) connect directly to the camera without requiring host kernel modules.

1. Open **Firefox** or **Microsoft Edge** inside your remote desktop session.
2. Navigate to [app.zoom.us/wc](https://app.zoom.us/wc) (Zoom Web Client) or click your meeting join link and select **"Join from Your Browser"**.
3. When prompted by the browser, click **"Allow"** to grant camera and microphone access.
4. Your redirected client webcam will stream smoothly with full HD video, virtual backgrounds, and audio.

---

## Approach 2: Native Zoom Desktop Client (with `v4l2loopback`)

The official Zoom Linux desktop application is a compiled C++ binary that only polls kernel V4L2 device nodes (`/dev/video*`). 

> [!WARNING]
> **Why `pw-v4l2 zoom` hangs:** 
> PipeWire's userspace wrapper (`pw-v4l2`) injects `libpw-v4l2.so` via `LD_PRELOAD`. Because the Zoom desktop application embeds a multi-process Chromium/CEF engine with sandboxed helper processes, the preloaded library gets inherited by child processes that lack socket permissions, causing an internal mutex deadlock on startup.
>
> The robust, standard Linux solution for the native Zoom desktop client is providing a virtual V4L2 loopback device.

### Step 1: Load `v4l2loopback` on the Docker Host

On the **host machine** running Docker (or Portainer):

```bash
# Install the loopback kernel module if not already installed
sudo apt update && sudo apt install -y v4l2loopback-dkms

# Load the module with exclusive_caps=1 (strictly required by Zoom and Chromium)
sudo modprobe v4l2loopback devices=1 video_nr=0 card_label="XRDP Camera" exclusive_caps=1
```

To ensure this module loads automatically on host reboot, create `/etc/modprobe.d/v4l2loopback.conf`:
```text
options v4l2loopback devices=1 video_nr=0 card_label="XRDP Camera" exclusive_caps=1
```
and add `v4l2loopback` to `/etc/modules-load.d/v4l2loopback.conf`.

### Step 2: Pass `/dev/video0` into your Container

In your `docker-compose.yml` or Portainer stack definition, map the device:

```yaml
services:
  desktop:
    image: ghcr.io/jmez11/linux-xrdp-desktop:latest
    devices:
      - /dev/dri:/dev/dri
      - /dev/video0:/dev/video0
```

*(Or via CLI: `docker run --device /dev/video0:/dev/video0 ...`)*.

### Step 3: Automatic Camera Bridging

Inside the container, `entrypoint.sh` automatically detects if `/dev/video0` is present. If found, it automatically starts a background GStreamer relay on session login:

```bash
gst-launch-1.0 pipewiresrc ! videoconvert ! videoscale ! video/x-raw,format=YUY2 ! v4l2sink device=/dev/video0 sync=false
```

### Step 4: Open Zoom Native

Launch the native Zoom application from the desktop launcher, dock, or terminal:
```bash
zoom
```
1. Open **Settings** (gear icon) → **Video**.
2. Under the **Camera** dropdown, select **"XRDP Camera"** (or `/dev/video0`).
3. Your live redirected video stream will display directly in Zoom.

---

## Troubleshooting

### Camera test inside container
To verify whether the camera frames are reaching the desktop independently of Zoom:
```bash
# Test direct PipeWire display
gst-launch-1.0 pipewiresrc ! videoconvert ! autovideosink

# Verify /dev/video0 loopback device capabilities
v4l2-ctl --device=/dev/video0 --all
```

### Edge / Chrome Camera Access
If using Microsoft Edge or Google Chrome, our automatic launcher wrappers ensure `--enable-features=WebRtcPipeWireCamera` is always supplied. If launched manually from custom scripts, append:
```bash
microsoft-edge --enable-features=WebRtcPipeWireCamera
```

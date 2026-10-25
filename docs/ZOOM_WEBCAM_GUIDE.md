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

# Load the module immediately for the current boot (with exclusive_caps=1 strictly required by Zoom)
sudo modprobe v4l2loopback devices=1 video_nr=0 card_label="XRDP Camera" exclusive_caps=1
```

#### Make it Persistent Across Host Reboots (Optional)
To automatically reload `v4l2loopback` with these options every time your Docker host boots, create the system configuration files with standard root read-only permissions (`chmod 644`):

1. **Module Options** (`/etc/modprobe.d/v4l2loopback.conf`):
   ```bash
   echo 'options v4l2loopback devices=1 video_nr=0 card_label="XRDP Camera" exclusive_caps=1' | sudo tee /etc/modprobe.d/v4l2loopback.conf
   sudo chmod 644 /etc/modprobe.d/v4l2loopback.conf
   ```

2. **Auto-Load on Boot** (`/etc/modules-load.d/v4l2loopback.conf`):
   ```bash
   echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf
   sudo chmod 644 /etc/modules-load.d/v4l2loopback.conf
   ```

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

### Step 3: On-Demand Camera Bridging

Inside the container, `entrypoint.sh` runs the on-demand multi-camera bridge daemon (`/usr/local/bin/xrdp-v4l2-bridge.py`) whenever `/dev/video0` is present.

**Streaming is strictly on-demand:**
- When you connect to RDP, your physical webcam **remains OFF** (the camera privacy light does not turn on).
- The bridge daemon continuously checks if any application (such as Zoom, OBS, VLC) is actively running or has opened `/dev/video*`.
- When an application accesses the device, the bridge starts streaming over RDP.
- When the application is closed or stops accessing the camera, the bridge automatically terminates the pipeline after a 3-second grace period, turning your physical webcam back OFF.

### Step 4: Open Zoom Native

Launch the native Zoom application from the desktop launcher, dock, or terminal:
```bash
zoom
```
1. Open **Settings** (gear icon) → **Video**.
2. Under the **Camera** dropdown, select **"XRDP Camera"** (or `/dev/video0`).
3. Your live redirected video stream will display directly in Zoom.

---

## Multiple Cameras Setup (Browsers & Standalone Apps)

RDP allows redirecting multiple webcams simultaneously (e.g. built-in laptop camera, external USB webcam, OBS virtual camera, capture card). The container supports up to 8 simultaneous cameras.

### 1. Selecting Multiple Cameras in your RDP Client

- **Windows Remote Desktop (`mstsc.exe`):**
  1. Click **Show Options** → **Local Resources** tab.
  2. Under *Local devices and resources*, click **More...**.
  3. Expand **Video capture devices** and tick **all** the cameras you want to redirect.
  4. Connect to your session.
- **FreeRDP:**
  Pass multiple camera parameters:
  ```bash
  xfreerdp /v:<host>:3389 /camera:device:0,format:h264 /camera:device:1,format:h264
  ```

### 2. In Web Browsers (Firefox, Edge, Chrome) — Zero Setup
All redirected cameras are published as independent native PipeWire sources (`xrdp-camera-0`, `xrdp-camera-1`, ...).
In Google Meet, Zoom Web, Teams Web, or webcamtests.com, the browser's camera selection dropdown will automatically list all of your redirected cameras by their client names (e.g., "Lenovo Performance RGB Camera", "Logitech Brio"). You can switch between cameras directly in the web app.

### 3. In Standalone Native Apps (Zoom Desktop, OBS, VLC)
To expose multiple cameras to native V4L2 apps, create multiple loopback devices on the host:

1. **Load `v4l2loopback` with multiple devices on Docker host:**
   ```bash
   sudo modprobe -r v4l2loopback 2>/dev/null || true
   sudo modprobe v4l2loopback devices=4 video_nr=0,1,2,3 card_label="XRDP Camera 1","XRDP Camera 2","XRDP Camera 3","XRDP Camera 4" exclusive_caps=1,1,1,1
   ```
   To make it persistent on host boot, put in `/etc/modprobe.d/v4l2loopback.conf`:
   ```text
   options v4l2loopback devices=4 video_nr=0,1,2,3 card_label="XRDP Camera 1","XRDP Camera 2","XRDP Camera 3","XRDP Camera 4" exclusive_caps=1,1,1,1
   ```

2. **Map all devices into your container:**
   ```yaml
   devices:
     - /dev/video0:/dev/video0
     - /dev/video1:/dev/video1
     - /dev/video2:/dev/video2
     - /dev/video3:/dev/video3
   ```

3. **On-Demand Mapping:**
   The container's `xrdp-v4l2-bridge.py` daemon monitors active requests and maps:
   - Camera 1 (`xrdp-camera-0`) → `/dev/video0` ("XRDP Camera 1")
   - Camera 2 (`xrdp-camera-1`) → `/dev/video1` ("XRDP Camera 2")
   - Camera 3 (`xrdp-camera-2`) → `/dev/video2` ("XRDP Camera 3")
   - Camera 4 (`xrdp-camera-3`) → `/dev/video3` ("XRDP Camera 4")

   Each camera only streams when an application accesses that specific device, preventing unnecessary CPU and bandwidth consumption.

In Zoom Desktop's **Settings → Video**, select between your cameras in the dropdown menu.

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

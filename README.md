# linux-xrdp-desktop

A full Ubuntu 24.04 **KDE Plasma** desktop in a Docker container, styled to look and feel like **macOS** — accessible over RDP with GPU-accelerated OpenGL, H.264 video encoding, webcam redirection (`[MS-RDPECAM]`), audio, and drive redirection. Built for a fast, responsive remote Linux desktop that actually plays video smoothly.

![Desktop](assets/wow-wallpaper.jpg)

## Features

- **Ubuntu 24.04 + KDE Plasma (macOS layout & styling)** — Configured out-of-the-box with the [How-To Geek KDE Plasma macOS transformation](https://www.howtogeek.com/heres-how-i-made-linux-feel-more-like-macos-using-kde-plasma/) and macOS Sonoma/Sequoia desktop experience:
  - **Top macOS Menu Bar** — Translucent top bar with User Switcher (profile icon), bold active Window Title (`%a`), Global Application Menu, System Tray, macOS-style Control Hub / Control Centre, and Digital Clock (`ddd MMM d` beside time)
  - **Top-Left macOS Desktop Widgets & Top-Right Macintosh HD** — Rounded macOS-style Calendar, Analog Clock, and live Weather widgets at the top-left, plus a **Macintosh HD** drive icon automatically arranged at the top-right
  - **Bottom macOS Dock** — Centered floating dock (`Fill Content` width, `Dodge Windows` visibility, 58px height) with colorful `Mkos-Big-Sur` icons for preinstalled apps (Finder/Dolphin, Firefox, VS Code, Konsole, Kate, Gwenview, Okular, GIMP, Inkscape, Blender, VLC, LibreOffice Writer/Calc, Calculator, System Settings) + Disks & Devices + Trash
  - **Smooth subpixel font rendering** — Configured with `Inter` + `Fira Code` fonts, RGB subpixel anti-aliasing, slight hinting (`hintslight`), and `lcddefault` filter across Qt, GTK, and X11
  - **Mkos-Big-Sur icons & Summaculate traffic-light window controls** — macOS Big Sur icon pack with Close/Minimize/Maximize traffic-light buttons positioned on the **top-left** (`ButtonsOnLeft=XIA`)
- **H.264 RDP encoding** — xrdp 0.10.3 + xorgxrdp 0.10.3 built from source with x264 (Ubuntu's xrdp 0.9.x has no H.264 support). Smooth video playback and snappy window dragging at 1080p
- **Webcam redirection (`[MS-RDPECAM]`)** — client cameras redirected over RDP Dynamic Virtual Channels (`RDPECAM`) are decoded (H.264 via OpenH264, plus raw YUY2/NV12/I420) and published as native PipeWire `Video/Source` camera nodes inside the container (no host `v4l2loopback` kernel module required)
- **TLS-encrypted** RDP on port 3389, multi-monitor support
- **Audio both ways** — PulseAudio playback and microphone redirection over RDP
- **Drive redirection (Windows-style Dolphin sidebar shortcuts)** — share client drives and they appear at `~/thinclient_drives/` via FUSE and automatically populate in Dolphin's left **Places** sidebar as `<Drive> on <ClientName>` (e.g. `C on NUCBOX`, `Y on NUCBOX`) when shared, or stay cleanly hidden when no storage is shared
- **Clipboard** redirection
- **VirtualGL** — GPU-accelerated OpenGL for headless servers (`vglrun glmark2` to test)
- **Preinstalled apps** — Dolphin, Konsole, Kate, Gwenview, Okular, Spectacle, KRunner (`Alt+Space`), Firefox, VS Code, GIMP, Inkscape, VLC, LibreOffice, Blender, htop, neofetch, git

## Quick start

### Portainer

Create a new stack, paste in [`docker-compose.portainer.yml`](docker-compose.portainer.yml), **change `RDP_PASS`**, and deploy.

### Docker Compose

```bash
git clone https://github.com/jmez11/linux-xrdp-desktop.git
cd linux-xrdp-desktop
# edit docker-compose.portainer.yml and set RDP_PASS
docker compose -f docker-compose.portainer.yml up -d
```

Then connect with any RDP client to `<host>:3389` and log in.

The image is also published to GHCR: `ghcr.io/jmez11/linux-xrdp-desktop:latest` (private — needs a `read:packages` token).

## Configuration

| Variable | Default | Description |
|---|---|---|
| `RDP_USER` | `engineer` | Desktop username (created on first start, has sudo) |
| `RDP_PASS` | `ChangeMe123!` | **Change this.** Login password |
| `TZ` | `UTC` | Timezone |
| `LIBVA_DRIVER_NAME` | `iHD` | VAAPI driver: `iHD` (Intel), `radeonsi` (AMD), omit for NVIDIA |

Home directory persists in the `rdp_home` Docker volume. Pass `/dev/dri` through for GPU access.

## Client setup (mstsc)

For the full experience, set these **before connecting** (Show Options):

- **Webcams** — Local Resources → More → Video capture devices → tick your camera(s) (or FreeRDP `/camera:device,format:h264`). Redirected cameras appear as PipeWire `Video/Source` nodes (`wpctl status`) and work out-of-the-box in Firefox WebRTC (`media.webrtc.camera.allow-pipewire` is pre-enabled); for V4L2-only apps, prefix with `pw-v4l2 <app>`
- **Drives** — Local Resources → More → Drives → tick your drives (appear at `~/thinclient_drives/`)
- **Audio playback** — Local Resources → Remote audio → Settings → *Play on this computer*
- **Microphone** — same dialog → *Record from this computer*

Drive shares only take effect on a fresh login — if you tick them mid-session, log out of KDE Plasma completely and reconnect.

## How it works

- `Dockerfile` builds everything: KDE Plasma desktop environment, macOS-style plasmoids (`org.kde.windowtitle`, `com.github.prayag2.controlcentre`, `org.macos.desktop.calendar`, `org.macos.desktop.clock`, `org.macos.desktop.weather`), `Mkos-Big-Sur` icons, `Summaculate` Aurorae window decorations, apps, and then compiles xrdp 0.10.3 + xorgxrdp 0.10.3 from source with `--enable-x264` and `--enable-rdpecam` (`xrdp-rdpecam/`, bringing `[MS-RDPECAM]` video capture + PipeWire camera sink and `PAKID_CORE_CLIENT_NAME` client computer name logging to `xrdp-chansrv`). Build dependencies are purged in-layer; a build-time check fails the image if any xrdp binary has missing shared libraries.
- `entrypoint.sh` creates the user, fixes home-directory ownership (Docker volumes mount root-owned, which breaks Xorg), prepares `/run/user/$UID` (`XDG_RUNTIME_DIR`), starts PipeWire + WirePlumber + XDG Desktop Portal (KDE + GTK) + `xrdp-drives-sync.py` alongside PulseAudio in `.xsession`, writes autostart entries, and launches `xrdp-sesman` + `xrdp`.
- `desktop-setup.sh` applies the KDE Plasma macOS two-panel layout, top-left Calendar/Clock/Weather widgets, top-right `Macintosh HD` desktop icon, Mkos-Big-Sur icon theme, Summaculate left-aligned traffic-light window buttons, smooth subpixel font config, and Breeze Dark color scheme on first login (sentinel-gated, so your tweaks persist).
- `xrdp-drives-sync.py` watches `~/thinclient_drives/` and `xrdp-chansrv`'s logged `PAKID_CORE_CLIENT_NAME` to dynamically populate Dolphin's left sidebar (`~/.local/share/user-places.xbel`) with `<Drive> on <ClientName>` entries whenever RDP storage is redirected.
- `pulseaudio-module-xrdp` is built from source against the image's PulseAudio (not packaged for 24.04).

## Limitations

- **Legacy V4L2-only camera apps**: Redirected webcams are published as userspace PipeWire `Video/Source` camera nodes (so the container does not require a host `v4l2loopback` kernel module). PipeWire/portal-aware apps like Firefox work directly; legacy apps that only open `/dev/video*` directly should be launched via `pw-v4l2 <app>`, or you can still pass a local host camera in with `--device=/dev/video0`.
- **RDP only**: no VNC/SSH in this image by design; it's a single-purpose desktop container.

## License

MIT — see [LICENSE](LICENSE).

# linux-xrdp-desktop

A full Ubuntu 24.04 XFCE desktop in a Docker container, accessible over RDP — with GPU-accelerated OpenGL, H.264 video encoding, audio, and drive redirection. Built for a fast, responsive remote Linux desktop that actually plays video smoothly.

![Desktop](assets/wow-wallpaper.jpg)

## Features

- **Ubuntu 24.04 + XFCE** — Arc-Dark theme, Papirus icons, dark aurora wallpaper
- **H.264 RDP encoding** — xrdp 0.10.3 + xorgxrdp 0.10.3 built from source with x264 (Ubuntu's xrdp 0.9.x has no H.264 support). Smooth video playback and snappy window dragging at 1080p
- **TLS-encrypted** RDP on port 3389, multi-monitor support
- **Audio both ways** — PulseAudio playback and microphone redirection over RDP
- **Drive redirection** — share client drives, they appear at `~/thinclient_drives/` via FUSE
- **Clipboard** redirection
- **VirtualGL** — GPU-accelerated OpenGL for headless servers (`vglrun glmark2` to test)
- **Preinstalled apps** — Firefox, VS Code, GIMP, Inkscape, VLC, LibreOffice, Blender, htop, neofetch, git

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

- **Drives** — Local Resources → More → Drives → tick your drives (appear at `~/thinclient_drives/`)
- **Audio playback** — Local Resources → Remote audio → Settings → *Play on this computer*
- **Microphone** — same dialog → *Record from this computer*

Drive shares only take effect on a fresh login — if you tick them mid-session, log out of XFCE completely and reconnect.

## How it works

- `Dockerfile` builds everything: desktop environment, apps, then compiles xrdp 0.10.3 + xorgxrdp 0.10.3 from source with `--enable-x264` (mirroring Ubuntu's build flags). Build dependencies are purged in-layer; a build-time check fails the image if any xrdp binary has missing shared libraries.
- `entrypoint.sh` creates the user, fixes home-directory ownership (Docker volumes mount root-owned, which breaks Xorg), writes XFCE autostart entries, and launches `xrdp-sesman` + `xrdp`.
- `desktop-setup.sh` applies theming on first login (sentinel-gated, so your tweaks persist).
- `pulseaudio-module-xrdp` is built from source against the image's PulseAudio (not packaged for 24.04).

## Limitations

- **Webcams**: xrdp has no video-capture channel, so client webcams can't be redirected over RDP. Microphone works; for video calls, use the client natively — or pass a host camera in with `--device=/dev/video0`.
- **RDP only**: no VNC/SSH in this image by design; it's a single-purpose desktop container.

## License

MIT — see [LICENSE](LICENSE).

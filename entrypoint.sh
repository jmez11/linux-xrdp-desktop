#!/bin/bash
set -e

USERNAME=${RDP_USER:-desktopuser}
PASSWORD=${RDP_PASS:-ChangeMe123!}

# Create isolated local user if missing
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
    usermod -aG video,render,audio "$USERNAME" 2>/dev/null || true
fi

# Ensure XDG_RUNTIME_DIR (/run/user/$UID) exists for PipeWire and XDG portals
# (Docker does not run systemd-logind, so /run/user/$UID is not created automatically)
USER_UID=$(id -u "$USERNAME")
mkdir -p -m 0700 "/run/user/$USER_UID"
chown "$USERNAME:$USERNAME" "/run/user/$USER_UID"

# User Xsession initialization: start PulseAudio, PipeWire camera graph + XDG
# portal, and KDE Plasma (X11) under DBus. Written idempotently on every container
# start so existing persistent /home volumes pick up KDE Plasma + PipeWire camera redirection.
mkdir -p "/home/$USERNAME"
cat << 'EOF' > "/home/$USERNAME/.xsession"
#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_SESSION_TYPE="x11"
export XDG_CURRENT_DESKTOP="KDE"
export XDG_SESSION_DESKTOP="KDE"
export KDE_FULL_SESSION="true"
export KDE_SESSION_VERSION="5"
export QT_QPA_PLATFORM="xcb"
mkdir -p -m 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

pulseaudio --start --exit-idle-time=-1 2>/dev/null || true
pacmd set-default-sink xrdp-sink 2>/dev/null || true
pacmd set-default-source xrdp-source 2>/dev/null || true

exec dbus-launch --exit-with-session bash -c '
    /usr/bin/pipewire >/dev/null 2>&1 &
    /usr/bin/wireplumber >/dev/null 2>&1 &
    /usr/lib/x86_64-linux-gnu/libexec/xdg-desktop-portal-kde >/dev/null 2>&1 &
    /usr/libexec/xdg-desktop-portal-gtk >/dev/null 2>&1 &
    /usr/libexec/xdg-desktop-portal >/dev/null 2>&1 &
    exec startplasma-x11
'
EOF
chmod +x "/home/$USERNAME/.xsession"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.xsession"

# The home directory is typically a Docker named volume, which mounts
# root-owned; useradd does not re-chown an existing mountpoint. The RDP
# session runs as the user and must be able to write here (Xorg log file,
# .Xauthority, XFCE config). Without this, Xorg fatals on startup with
# "Cannot open log file" (exit code 1, no log written) and sesman reports
# "Timed out waiting for X server" / "Error connecting to user session".
if [ -d "/home/$USERNAME" ]; then
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
fi

# Desktop wow factor: first-run beautification script + plank dock, launched
# via XFCE autostart inside the user session. Written idempotently on every
# container start; the setup script itself is sentinel-gated.
mkdir -p "/home/$USERNAME/.config/autostart"
cat > "/home/$USERNAME/.config/autostart/xrdp-desktop-setup.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=XRDP Desktop Setup
Comment=One-time desktop theming (theme, wallpaper, compositor)
Exec=/usr/local/bin/desktop-setup.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
# Plank is gone (it needs a compositor to render, and compositing kills RDP
# performance); remove the stale autostart entry from existing volumes.
rm -f "/home/$USERNAME/.config/autostart/plank.desktop"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config/autostart"

# Dynamically map host DRI render node GID to avoid permission errors
if [ -e /dev/dri/renderD128 ]; then
    RENDER_GID=$(stat -c '%g' /dev/dri/renderD128)
    if ! getent group "$RENDER_GID" >/dev/null; then
        groupadd -g "$RENDER_GID" host-render 2>/dev/null || true
    fi
    RENDER_GROUP_NAME=$(getent group "$RENDER_GID" | cut -d: -f1)
    usermod -aG "$RENDER_GROUP_NAME" "$USERNAME" 2>/dev/null || true
fi

# Configure VirtualGL headless EGL display
/opt/VirtualGL/bin/vglserver_config -config +s +f +t 2>/dev/null || true
cat << 'EOF' > /etc/profile.d/virtualgl.sh
export PATH="/opt/VirtualGL/bin:$PATH"
export VGL_DISPLAY="egl"
export VGL_COMPRESS="proxy"
export VGL_FPS="60"
EOF
chmod +x /etc/profile.d/virtualgl.sh

adduser "$USERNAME" ssl-cert 2>/dev/null || true

# Clean stale sockets/locks. xrdp 0.10.x keeps its PID files directly under
# /var/run/ (not /var/run/xrdp/), and a stale one makes sesman refuse to start
# ("already running"), which then kills xrdp and sends the container into a
# restart loop. Only remove a PID file if its process is actually gone.
mkdir -p /var/run/xrdp/pulse
chmod 777 /var/run/xrdp/pulse
rm -rf /var/run/xrdp/* /tmp/.X* /tmp/.xrdp*
for pidfile in /var/run/xrdp-sesman.pid /var/run/xrdp.pid; do
    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile" 2>/dev/null || echo "")
        if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pidfile"
        fi
    fi
done

/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon

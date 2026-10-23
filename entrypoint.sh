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

    # User Xsession initialization: start PulseAudio and XFCE under DBus
    cat << 'EOF' > "/home/$USERNAME/.xsession"
#!/bin/bash
pulseaudio --start --exit-idle-time=-1 2>/dev/null || true
pacmd set-default-sink xrdp-sink 2>/dev/null || true
pacmd set-default-source xrdp-source 2>/dev/null || true
exec dbus-launch --exit-with-session startxfce4
EOF
    chmod +x "/home/$USERNAME/.xsession"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.xsession"
fi

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

# Clean stale sockets/locks
mkdir -p /var/run/xrdp/pulse
chmod 777 /var/run/xrdp/pulse
rm -rf /var/run/xrdp/* /tmp/.X* /tmp/.xrdp*

/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon

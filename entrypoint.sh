#!/bin/bash
set -e

USERNAME=${RDP_USER:-desktopuser}
PASSWORD=${RDP_PASS:-ChangeMe123!}

# Configure system timezone from container environment (e.g. TZ=America/Los_Angeles in compose)
TZ_VALUE="${TZ:-UTC}"
if [ -e "/usr/share/zoneinfo/$TZ_VALUE" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ_VALUE" /etc/localtime
    echo "$TZ_VALUE" > /etc/timezone
    sed -i '/^TZ=/d' /etc/environment 2>/dev/null || true
    echo "TZ=$TZ_VALUE" >> /etc/environment
fi

# Create isolated local user if missing
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -c "$USERNAME" "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
    usermod -aG video,render,audio "$USERNAME" 2>/dev/null || true
fi
if [ -z "$(getent passwd "$USERNAME" | cut -d: -f5)" ]; then
    chfn -f "$USERNAME" "$USERNAME" 2>/dev/null || usermod -c "$USERNAME" "$USERNAME" 2>/dev/null || true
fi

# Grant passwordless sudo for package management & administrative tasks inside the container
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USERNAME" > "/etc/sudoers.d/90-$USERNAME"
chmod 0440 "/etc/sudoers.d/90-$USERNAME"

# Ensure XDG_RUNTIME_DIR (/run/user/$UID) exists for PipeWire and XDG portals
# (Docker does not run systemd-logind, so /run/user/$UID is not created automatically)
USER_UID=$(id -u "$USERNAME")
mkdir -p -m 0700 "/run/user/$USER_UID"
chown "$USERNAME:$USERNAME" "/run/user/$USER_UID"

mkdir -p "/home/$USERNAME/Desktop" "/home/$USERNAME/Downloads" "/home/$USERNAME/Documents" "/home/$USERNAME/.config"

# Clean stale Chromium / Edge / Chrome lock files from persistent volume
rm -f "/home/$USERNAME/.config/microsoft-edge/Singleton"* \
      "/home/$USERNAME/.config/google-chrome/Singleton"* \
      "/home/$USERNAME/.config/chromium/Singleton"* 2>/dev/null || true

# Guarantee XDG user dirs explicitly point Desktop to ~/Desktop from the very first session start
cat << 'EOF' > "/home/$USERNAME/.config/user-dirs.dirs"
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF

cat << 'EOF' > "/home/$USERNAME/Desktop/System Drive.desktop"
[Desktop Entry]
Type=Link
Name=System Drive
Icon=/usr/share/icons/Mkos-Big-Sur/128x128/devices/disk.svg
URL=file:///
EOF
chmod +x "/home/$USERNAME/Desktop/System Drive.desktop"

# Pre-configure VS Code arguments to disable hardware acceleration on software displays
mkdir -p "/home/$USERNAME/.vscode" "/home/$USERNAME/.config/Code"
cat << 'EOF' > "/home/$USERNAME/.vscode/argv.json"
{
    "enable-crash-reporter": false,
    "disable-hardware-acceleration": true,
    "password-store": "basic"
}
EOF
cp "/home/$USERNAME/.vscode/argv.json" "/home/$USERNAME/.config/Code/argv.json" 2>/dev/null || true

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
unset GTK_MODULES GTK3_MODULES
export UBUNTU_MENUPROXY=0
if [ -f /etc/timezone ]; then
    export TZ="$(cat /etc/timezone)"
elif [ -e /etc/localtime ]; then
    export TZ="$(realpath /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
fi
if [ ! -e /dev/dri/renderD128 ]; then
    unset LIBVA_DRIVER_NAME
fi
mkdir -p -m 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

pulseaudio --start --exit-idle-time=-1 2>/dev/null || true
pacmd set-default-sink xrdp-sink 2>/dev/null || true
pacmd set-default-source xrdp-source 2>/dev/null || true

# Apply smooth Xft subpixel font anti-aliasing and 96 DPI for X11 apps
cat << 'XRES' | xrdb -merge 2>/dev/null || true
Xft.antialias: 1
Xft.hinting: 1
Xft.hintstyle: hintslight
Xft.rgba: rgb
Xft.lcdfilter: lcddefault
Xft.dpi: 96
XRES

exec dbus-launch --exit-with-session bash -c '
    /usr/bin/pipewire >/dev/null 2>&1 &
    /usr/bin/wireplumber >/dev/null 2>&1 &
    /usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1 >/dev/null 2>&1 &
    /usr/lib/x86_64-linux-gnu/libexec/xdg-desktop-portal-kde >/dev/null 2>&1 &
    /usr/libexec/xdg-desktop-portal-gtk >/dev/null 2>&1 &
    /usr/libexec/xdg-desktop-portal >/dev/null 2>&1 &
    /usr/local/bin/xrdp-drives-sync.py >/dev/null 2>&1 &
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

# Start system D-Bus, polkitd, and AccountsService so KDE System Settings
# (Users KCM, Change Avatar, etc.) and desktop portals have a working system bus.
mkdir -p /var/run/dbus /var/lib/AccountsService/users /var/lib/AccountsService/icons
rm -f /var/run/dbus/pid
dbus-uuidgen --ensure 2>/dev/null || true
dbus-daemon --system --fork 2>/dev/null || true
if [ ! -f "/home/$USERNAME/.face.icon" ] && [ -f /usr/share/plasma/avatars/photos/Astronaut.png ]; then
    cp /usr/share/plasma/avatars/photos/Astronaut.png "/home/$USERNAME/.face.icon"
    cp /usr/share/plasma/avatars/photos/Astronaut.png "/var/lib/AccountsService/icons/$USERNAME"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.face.icon"
fi
if [ ! -f "/var/lib/AccountsService/users/$USERNAME" ]; then
    printf '[User]\nSystemAccount=false\nIcon=/var/lib/AccountsService/icons/%s\n' "$USERNAME" > "/var/lib/AccountsService/users/$USERNAME"
fi
for bin in /usr/lib/polkit-1/polkitd /usr/libexec/polkitd; do
    if [ -x "$bin" ]; then "$bin" --no-debug >/dev/null 2>&1 & break; fi
done
for bin in /usr/libexec/accounts-daemon /usr/lib/accountsservice/accounts-daemon; do
    if [ -x "$bin" ]; then "$bin" >/dev/null 2>&1 & break; fi
done
if [ -x /usr/local/bin/xrdp-timedate-daemon.py ]; then
    /usr/local/bin/xrdp-timedate-daemon.py >/dev/null 2>&1 &
fi
sleep 0.5
dbus-send --system --print-reply --dest=org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts.CacheUser string:"$USERNAME" >/dev/null 2>&1 || true
dbus-send --system --print-reply --dest=org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts.FindUserByName string:"$USERNAME" >/dev/null 2>&1 || true

/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon

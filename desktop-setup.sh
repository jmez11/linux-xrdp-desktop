#!/bin/bash
# One-time desktop beautification for the XRDP container.
# Runs inside the user session via XFCE autostart. Applies the dark theme,
# wallpaper, compositor and terminal font once (sentinel-gated, so the user's
# own tweaks are never overwritten), then opens a welcome terminal.
set -u

SENTINEL="$HOME/.config/xrdp-desktop-setup-v2.done"
[ -f "$SENTINEL" ] && exit 0

WALLPAPER="/usr/share/backgrounds/xrdp-wow.jpg"

# Wait for the xfconf daemon to be reachable (up to ~30s)
for _ in $(seq 1 15); do
    xfconf-query -c xsettings -p /Net/ThemeName >/dev/null 2>&1 && break
    sleep 2
done

# Dark GTK + window + icon theme
xfconf-query -c xsettings -p /Net/ThemeName -s "Arc-Dark" 2>/dev/null || true
xfconf-query -c xsettings -p /Net/IconThemeName -s "Papirus-Dark" 2>/dev/null || true
xfconf-query -c xfwm4 -p /general/theme -s "Arc-Dark" 2>/dev/null || true

# Compositor OFF: software compositing over RDP makes every window drag
# re-composite and re-encode the full screen (the 1+ second lag). The dark
# theme + wallpaper carry the look on their own.
xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true

# Wallpaper on every monitor / workspace
if [ -f "$WALLPAPER" ]; then
    for prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$'); do
        xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" 2>/dev/null || true
    done
fi

# Terminal: Fira Code
xfconf-query -c xfce4-terminal -p /font-name -s "Fira Code Retina 11" 2>/dev/null || true

mkdir -p "$(dirname "$SENTINEL")"
touch "$SENTINEL"

# First-login wow: terminal with system info
if command -v xfce4-terminal >/dev/null 2>&1 && command -v neofetch >/dev/null 2>&1; then
    xfce4-terminal -e "bash -c 'neofetch; exec bash'" &
fi

exit 0

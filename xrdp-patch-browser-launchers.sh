#!/bin/bash
# xrdp-patch-browser-launchers.sh: Ensures all Chromium-based browsers
# (Microsoft Edge, Google Chrome, Brave, Chromium) automatically launch
# with --enable-features=WebRtcPipeWireCamera across:
#   1. .desktop shortcuts (KDE Kickoff, Dock, Desktop icons)
#   2. /usr/bin/ and /usr/local/bin/ absolute path invocations
#   3. Terminal / CLI calls

WRAPPER="/usr/local/bin/chromium-browser-wrapper"
[ -x "$WRAPPER" ] || exit 0

# 1. Overwrite /usr/bin symlinks so any tool or launcher calling /usr/bin directly hits the wrapper
for bin in microsoft-edge microsoft-edge-stable google-chrome google-chrome-stable brave-browser chromium chromium-browser; do
    REAL_EXISTS=0
    case "$bin" in
        *edge*) [ -d /opt/microsoft/msedge ] && REAL_EXISTS=1 ;;
        *chrome*) [ -d /opt/google/chrome ] && REAL_EXISTS=1 ;;
        *brave*) [ -d /opt/brave.com/brave ] && REAL_EXISTS=1 ;;
        *chromium*) ([ -d /usr/lib/chromium-browser ] || [ -d /usr/lib/chromium ]) && REAL_EXISTS=1 ;;
    esac
    if [ "$REAL_EXISTS" -eq 1 ]; then
        ln -sf "$WRAPPER" "/usr/bin/$bin" 2>/dev/null || true
        ln -sf "$WRAPPER" "/usr/local/bin/$bin" 2>/dev/null || true
    fi
done

# 2. Patch all .desktop launchers so KDE Application Launcher / Dock shortcuts include the flag directly
DESKTOP_DIRS=(
    "/usr/share/applications"
    /home/*/.local/share/applications
    /home/*/Desktop
)

for dir in "${DESKTOP_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for d in "$dir"/microsoft-edge*.desktop "$dir"/google-chrome*.desktop "$dir"/chromium*.desktop "$dir"/brave*.desktop; do
        [ -f "$d" ] || continue
        if ! grep -q "WebRtcPipeWireCamera" "$d"; then
            sed -i 's|^Exec=\([^ ]*\)\(.*%U\)|Exec=\1 --enable-features=WebRtcPipeWireCamera\2|' "$d" 2>/dev/null || true
            sed -i 's|^Exec=\([^ ]*\)\(.*%u\)|Exec=\1 --enable-features=WebRtcPipeWireCamera\2|' "$d" 2>/dev/null || true
            if ! grep -q "WebRtcPipeWireCamera" "$d"; then
                sed -i '/^Exec=/ s/$/ --enable-features=WebRtcPipeWireCamera/' "$d" 2>/dev/null || true
            fi
        fi
    done
done

update-desktop-database /usr/share/applications 2>/dev/null || true
kbuildsycoca5 >/dev/null 2>&1 || true

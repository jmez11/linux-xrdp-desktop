#!/bin/bash
# Automatically install clicked .deb package(s) in the XRDP desktop container:
# - Updates APT package sources automatically when missing or stale (> 1 hour)
# - Resolves and installs all dependencies via apt-get install -y
# - Fixes Electron/Chromium sandbox flags on newly installed .desktop launchers
#   so apps like Chrome, Discord, Slack, etc. work inside the container
# - Shows KDE desktop notifications / kdialog progress
set -u

if [ "$#" -eq 0 ]; then
    exit 0
fi

notify() {
    local title="$1"
    local body="$2"
    local icon="${3:-system-software-install}"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Package Installer" -i "$icon" "$title" "$body" 2>/dev/null || true
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --title "$title" --passivepopup "$body" 5 2>/dev/null || true
    fi
}

DEB_FILES=()
DEB_NAMES=()
for arg in "$@"; do
    # Strip file:// URI prefix if passed as a URL
    path="${arg#file://}"
    path="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$path" 2>/dev/null || echo "$path")"
    if [ -f "$path" ]; then
        DEB_FILES+=("$path")
        DEB_NAMES+=("$(basename "$path")")
    fi
done

if [ "${#DEB_FILES[@]}" -eq 0 ]; then
    notify "Package Installation Failed" "No valid .deb file found." "dialog-error"
    exit 1
fi

NAMES_STR="${DEB_NAMES[*]}"
notify "Installing Package" "Updating package sources and installing ${NAMES_STR}..." "system-software-install"

LOG_FILE="/tmp/xrdp-deb-install-$$.log"

(
    export DEBIAN_FRONTEND=noninteractive

    # Refresh apt lists if empty or older than 60 minutes
    NEED_UPDATE=1
    if [ -d /var/lib/apt/lists ] && [ -n "$(ls -A /var/lib/apt/lists 2>/dev/null)" ]; then
         latest=$(find /var/lib/apt/lists -maxdepth 1 -type f -mmin -60 2>/dev/null | head -1)
        [ -n "$latest" ] && NEED_UPDATE=0
    fi

    if [ "$NEED_UPDATE" -eq 1 ]; then
        sudo -n apt-get update -y
    fi

    sudo -n apt-get install -y --fix-broken "${DEB_FILES[@]}" || {
        sudo -n apt-get update -y
        sudo -n apt-get install -y --fix-broken "${DEB_FILES[@]}"
    }

    # Ensure KDE desktop database is refreshed after installing new .desktop files
    update-desktop-database /usr/share/applications 2>/dev/null || true
) >"$LOG_FILE" 2>&1
RC=$?

if [ "$RC" -eq 0 ]; then
    kbuildsycoca5 >/dev/null 2>&1 || true
    notify "Package Installed" "Successfully installed ${NAMES_STR}." "emblem-checked"
    rm -f "$LOG_FILE"
    exit 0
else
    ERR_TAIL="$(tail -n 15 "$LOG_FILE" 2>/dev/null)"
    notify "Package Installation Failed" "Failed to install ${NAMES_STR}." "dialog-error"
    if command -v kdialog >/dev/null 2>&1; then
        kdialog --title "Package Installation Failed (${NAMES_STR})" --error "$ERR_TAIL" 2>/dev/null || true
    fi
    exit "$RC"
fi

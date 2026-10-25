#!/usr/bin/env python3
"""
xrdp-camera-portal-setup.py: Pre-authorizes camera, microphone, and speaker
permissions in the XDG Desktop Portal PermissionStore so web browsers and
desktop apps (Firefox, Chrome, Edge, Brave, Chromium, Opera, Zoom, etc.)
receive instant platform approval and display native in-browser permission prompts.
"""

import time
import sys

APPS = [
    "",  # Universal wildcard for all native / non-sandboxed host applications
    "firefox",
    "firefox-esr",
    "org.mozilla.firefox",
    "google-chrome",
    "google-chrome-stable",
    "com.google.Chrome",
    "microsoft-edge",
    "microsoft-edge-stable",
    "com.microsoft.Edge",
    "chromium",
    "chromium-browser",
    "org.chromium.Chromium",
    "brave-browser",
    "com.brave.Browser",
    "opera",
    "opera-stable",
    "com.opera.Opera",
    "vivaldi",
    "vivaldi-stable",
    "com.vivaldi.Vivaldi",
    "zoom",
    "us.zoom.Zoom",
    "teams",
    "com.microsoft.Teams",
    "slack",
    "discord",
    "obs",
    "com.obsproject.Studio",
]

RESOURCES = [
    ("devices", "camera"),
    ("devices", "microphone"),
    ("devices", "speakers"),
]

def main():
    try:
        import dbus
    except ImportError:
        sys.exit(0)

    bus = None
    try:
        bus = dbus.SessionBus()
    except Exception:
        sys.exit(0)

    store = None
    # Wait up to 15 seconds for PermissionStore D-Bus service to be reachable
    for _ in range(30):
        try:
            proxy = bus.get_object(
                "org.freedesktop.impl.portal.PermissionStore",
                "/org/freedesktop/impl/portal/PermissionStore"
            )
            store = dbus.Interface(proxy, "org.freedesktop.impl.portal.PermissionStore")
            # Probe lookup to ensure the service is responsive
            store.Lookup("devices", "camera")
            break
        except Exception:
            time.sleep(0.5)

    if not store:
        sys.exit(0)

    for table, resource_id in RESOURCES:
        for app in APPS:
            try:
                store.SetPermission(table, True, resource_id, app, ["yes"])
            except Exception:
                pass

if __name__ == "__main__":
    main()

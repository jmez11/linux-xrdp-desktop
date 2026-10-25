#!/usr/bin/env python3
"""
Helper script for the macOS Animated Dock in XRDP.
Handles reading, pinning, unpinning, and drag-and-drop parsing of applications
to ~/.config/dock-apps.json.
"""
import sys
import os
import json
import glob
import urllib.parse
import configparser

DOCK_CONF = os.path.expanduser("~/.config/dock-apps.json")

DEFAULT_APPS = [
    {"name": "Dolphin", "appMatch": "dolphin", "iconName": "/usr/share/icons/breeze-dark/apps/48/system-file-manager.svg", "cmd": "dolphin", "isSeparatorBefore": False},
    {"name": "Firefox", "appMatch": "firefox", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/firefox.svg", "cmd": "firefox", "isSeparatorBefore": False},
    {"name": "Visual Studio Code", "appMatch": "code", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/vscode.svg", "cmd": "/usr/local/bin/vscode-launch", "isSeparatorBefore": False},
    {"name": "Konsole", "appMatch": "konsole", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/utilities-terminal.svg", "cmd": "konsole", "isSeparatorBefore": False},
    {"name": "Kate", "appMatch": "kate", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/kate.svg", "cmd": "kate", "isSeparatorBefore": False},
    {"name": "Gwenview", "appMatch": "gwenview", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/gwenview.svg", "cmd": "gwenview", "isSeparatorBefore": False},
    {"name": "Okular", "appMatch": "okular", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/okular.svg", "cmd": "okular", "isSeparatorBefore": False},
    {"name": "GIMP", "appMatch": "gimp", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/gimp.svg", "cmd": "gimp", "isSeparatorBefore": False},
    {"name": "Inkscape", "appMatch": "inkscape", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/inkscape.svg", "cmd": "inkscape", "isSeparatorBefore": False},
    {"name": "Blender", "appMatch": "blender", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/blender.svg", "cmd": "blender", "isSeparatorBefore": False},
    {"name": "OBS Studio", "appMatch": "obs", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/obs.svg", "cmd": "obs", "isSeparatorBefore": False},
    {"name": "VLC", "appMatch": "vlc", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/vlc.svg", "cmd": "vlc", "isSeparatorBefore": False},
    {"name": "LibreOffice Writer", "appMatch": "writer", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/libreoffice-writer.svg", "cmd": "libreoffice --writer", "isSeparatorBefore": False},
    {"name": "LibreOffice Calc", "appMatch": "calc", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/libreoffice-calc.svg", "cmd": "libreoffice --calc", "isSeparatorBefore": False},
    {"name": "Calculator", "appMatch": "kcalc", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/accessories-calculator.svg", "cmd": "kcalc", "isSeparatorBefore": False},
    {"name": "System Settings", "appMatch": "systemsettings", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/apps/systemsettings.svg", "cmd": "systemsettings5", "isSeparatorBefore": False},
    {"name": "Shared Drives", "appMatch": "thinclient_drives", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/devices/drive-harddisk.svg", "cmd": "dolphin ~/thinclient_drives", "isSeparatorBefore": True},
    {"name": "Trash", "appMatch": "trash", "iconName": "/usr/share/icons/Mkos-Big-Sur/128x128/places/user-trash-full.svg", "cmd": "dolphin trash:/", "isSeparatorBefore": False}
]

def load_apps():
    if os.path.exists(DOCK_CONF):
        try:
            with open(DOCK_CONF, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list) and len(data) > 0:
                    return data
        except Exception:
            pass
    return list(DEFAULT_APPS)

def save_apps(apps):
    os.makedirs(os.path.dirname(DOCK_CONF), exist_ok=True)
    with open(DOCK_CONF, "w", encoding="utf-8") as f:
        json.dump(apps, f, indent=2)

def find_desktop_file(target):
    target = target.strip()
    target = urllib.parse.unquote(target)
    if target.startswith("file://"):
        target = target[7:]
    if target.startswith("applications:"):
        target = target[13:]

    # If target is already a valid .desktop file path
    if os.path.isfile(target) and target.endswith(".desktop"):
        return target

    # If target is an executable binary or script directly
    if os.path.isfile(target) and os.access(target, os.X_OK):
        name = os.path.splitext(os.path.basename(target))[0]
        return {
            "name": name.capitalize(),
            "appMatch": name.lower(),
            "iconName": "application-x-executable",
            "cmd": target,
            "isSeparatorBefore": False
        }

    search_dirs = [
        os.path.expanduser("~/.local/share/applications"),
        "/usr/share/applications",
        "/usr/local/share/applications",
        "/var/lib/snapd/desktop/applications",
        "/var/lib/flatpak/exports/share/applications"
    ]

    base = os.path.basename(target)
    name_no_ext = base[:-8] if base.endswith(".desktop") else base

    # 1. Look for exact <name>.desktop in search_dirs
    candidate_names = [base if base.endswith(".desktop") else f"{base}.desktop", f"{name_no_ext}.desktop"]
    for d in search_dirs:
        for cname in candidate_names:
            cpath = os.path.join(d, cname)
            if os.path.isfile(cpath):
                return cpath

    # 2. Look for case-insensitive match or contains match
    clean_key = name_no_ext.lower()
    for d in search_dirs:
        if not os.path.isdir(d):
            continue
        try:
            for fname in os.listdir(d):
                if fname.lower().endswith(".desktop"):
                    fl = fname.lower()
                    if clean_key in fl or fl.replace(".desktop", "") in clean_key:
                        return os.path.join(d, fname)
        except Exception:
            pass
    return None

def parse_desktop_file(path_or_dict):
    if isinstance(path_or_dict, dict):
        return path_or_dict
    cp = configparser.ConfigParser(interpolation=None)
    try:
        cp.read(path_or_dict, encoding="utf-8")
        entry = cp["Desktop Entry"]
    except Exception:
        return None
    name = entry.get("Name", os.path.splitext(os.path.basename(path_or_dict))[0])
    exec_cmd = entry.get("Exec", "")
    for flag in ["%f", "%F", "%u", "%U", "%i", "%c", "%k"]:
        exec_cmd = exec_cmd.replace(flag, "")
    exec_cmd = exec_cmd.strip()
    icon = entry.get("Icon", "application-x-executable")

    # If Big Sur theme has a matching SVG, prefer it
    mkos_svg = f"/usr/share/icons/Mkos-Big-Sur/128x128/apps/{icon}.svg"
    if os.path.isfile(mkos_svg):
        icon = mkos_svg

    first_token = exec_cmd.split()[0] if exec_cmd else "app"
    app_match = os.path.basename(first_token).lower()
    return {
        "name": name,
        "appMatch": app_match,
        "iconName": icon,
        "cmd": exec_cmd,
        "isSeparatorBefore": False
    }

def add_app(target):
    desktop_target = find_desktop_file(target)
    if not desktop_target:
        print(json.dumps(load_apps()))
        return
    parsed = parse_desktop_file(desktop_target)
    if not parsed:
        print(json.dumps(load_apps()))
        return
    apps = load_apps()
    for app in apps:
        if app.get("cmd") == parsed["cmd"] or app.get("name") == parsed["name"]:
            # Already exists
            print(json.dumps(apps))
            return
    # Insert before the last two items (Shared Drives and Trash)
    insert_pos = max(0, len(apps) - 2)
    apps.insert(insert_pos, parsed)
    save_apps(apps)
    print(json.dumps(apps))

def remove_app(target):
    apps = load_apps()
    idx = -1
    try:
        idx = int(target)
    except ValueError:
        target_lower = target.lower()
        for i, a in enumerate(apps):
            if a.get("name", "").lower() == target_lower or a.get("appMatch", "").lower() == target_lower:
                idx = i
                break
    if 0 <= idx < len(apps):
        app_match = apps[idx].get("appMatch", "")
        if app_match not in ("trash", "thinclient_drives"):
            apps.pop(idx)
            save_apps(apps)
    print(json.dumps(apps))

def move_app(from_idx, to_idx):
    apps = load_apps()
    try:
        f = int(from_idx)
        t = int(to_idx)
        if 0 <= f < len(apps) and 0 <= t < len(apps):
            item = apps.pop(f)
            apps.insert(t, item)
            save_apps(apps)
    except Exception:
        pass
    print(json.dumps(apps))

def save_custom_apps(json_str):
    try:
        data = json.loads(json_str)
        if isinstance(data, list) and len(data) > 0:
            save_apps(data)
            print(json.dumps(data))
            return
    except Exception:
        pass
    print(json.dumps(load_apps()))

def dump_apps():
    print(json.dumps(load_apps()))

def init_apps():
    if not os.path.exists(DOCK_CONF):
        save_apps(DEFAULT_APPS)
    print(json.dumps(load_apps()))

def main():
    if len(sys.argv) < 2:
        dump_apps()
        return
    cmd = sys.argv[1]
    if cmd == "init":
        init_apps()
    elif cmd == "dump":
        dump_apps()
    elif cmd == "add" and len(sys.argv) >= 3:
        add_app(sys.argv[2])
    elif cmd == "remove" and len(sys.argv) >= 3:
        remove_app(sys.argv[2])
    elif cmd == "move" and len(sys.argv) >= 4:
        move_app(sys.argv[2], sys.argv[3])
    elif cmd == "save" and len(sys.argv) >= 3:
        save_custom_apps(sys.argv[2])
    elif cmd == "list":
        for i, a in enumerate(load_apps()):
            print(f"[{i}] {a.get('name')} ({a.get('cmd')})")
    else:
        dump_apps()

if __name__ == "__main__":
    main()

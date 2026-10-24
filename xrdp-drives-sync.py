#!/usr/bin/env python3
"""
Synchronize XRDP redirected drives (~/thinclient_drives/*) into Dolphin's Places
sidebar (~/.local/share/user-places.xbel) using Windows-style naming:
  "<Drive> on <ClientName>" (e.g., "C on NUCBOX", "Y on NUCBOX")
and never fail if no storage is redirected.
"""
import glob
import os
import re
import time
import xml.etree.ElementTree as ET

HOME = os.path.expanduser("~")
THINCLIENT_DIR = os.path.join(HOME, "thinclient_drives")
XBEL_PATH = os.path.join(HOME, ".local", "share", "user-places.xbel")

INTERNAL_ENTRIES = {".clipboard", "..", "."}


def get_client_name() -> str:
    """Parse the connected RDP client computer name from xrdp-chansrv log."""
    display = os.environ.get("DISPLAY", ":10").lstrip(":").split(".")[0]
    candidates = [
        os.path.join(HOME, f"xrdp-chansrv.{display}.log"),
        os.path.join(HOME, ".local", "share", "xrdp", f"xrdp-chansrv.{display}.log"),
    ]
    candidates.extend(sorted(glob.glob(os.path.join(HOME, "xrdp-chansrv.*.log")), reverse=True))
    candidates.extend(
        sorted(glob.glob(os.path.join(HOME, ".local", "share", "xrdp", "xrdp-chansrv.*.log")), reverse=True)
    )

    pattern = re.compile(r"RDPDR client computer name:\s*'([^']+)'")
    for log_path in candidates:
        if not os.path.isfile(log_path):
            continue
        try:
            with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
                matches = pattern.findall(f.read())
                if matches:
                    name = matches[-1].strip().rstrip("\x00")
                    if name:
                        return name
        except OSError:
            continue
    return ""


def get_redirected_drives() -> list[str]:
    """Return sorted list of user-shared drives under ~/thinclient_drives."""
    if not os.path.isdir(THINCLIENT_DIR):
        return []
    try:
        entries = []
        for entry in os.listdir(THINCLIENT_DIR):
            if entry in INTERNAL_ENTRIES or entry.startswith("."):
                continue
            full_path = os.path.join(THINCLIENT_DIR, entry)
            if os.path.isdir(full_path):
                entries.append(entry)
        return sorted(entries)
    except OSError:
        return []


def format_drive_label(drive_name: str, client_name: str) -> str:
    clean_drive = drive_name.rstrip(":$")
    if client_name:
        return f"{clean_drive} on {client_name}"
    return f"{clean_drive} (Remote Drive)"


def ensure_default_xbel() -> ET.ElementTree:
    os.makedirs(os.path.dirname(XBEL_PATH), exist_ok=True)
    if os.path.isfile(XBEL_PATH):
        try:
            return ET.parse(XBEL_PATH)
        except Exception:
            pass

    root = ET.Element(
        "xbel",
        {
            "xmlns:bookmark": "http://www.freedesktop.org/standards/desktop-bookmarks",
            "xmlns:mime": "http://www.freedesktop.org/standards/shared-mime-info",
            "xmlns:kdepriv": "http://www.kde.org/kdepriv",
        },
    )
    default_places = [
        (f"file://{HOME}", "Home", "user-home"),
        (f"file://{HOME}/Desktop", "Desktop", "user-desktop"),
        (f"file://{HOME}/Documents", "Documents", "folder-documents"),
        (f"file://{HOME}/Downloads", "Downloads", "folder-downloads"),
        ("trash:/", "Trash", "user-trash"),
    ]
    for href, title_text, icon_name in default_places:
        bm = ET.SubElement(root, "bookmark", {"href": href})
        title = ET.SubElement(bm, "title")
        title.text = title_text
        info = ET.SubElement(bm, "info")
        meta_kde = ET.SubElement(info, "metadata", {"owner": "http://www.kde.org"})
        is_sys = ET.SubElement(meta_kde, "isSystemItem")
        is_sys.text = "true"
        meta_fd = ET.SubElement(info, "metadata", {"owner": "http://freedesktop.org"})
        ET.SubElement(meta_fd, "bookmark:icon", {"name": icon_name})

    return ET.ElementTree(root)


def sync_places(drives: list[str], client_name: str) -> None:
    tree = ensure_default_xbel()
    root = tree.getroot()

    # Remove previous thinclient_drives bookmark entries so stale shares disappear cleanly
    to_remove = []
    for bm in root.findall("bookmark"):
        href = bm.attrib.get("href", "")
        if f"file://{THINCLIENT_DIR}" in href:
            to_remove.append(bm)
    for bm in to_remove:
        root.remove(bm)

    # If drives are shared, add each drive as "<Drive> on <ClientName>" (like Windows Explorer)
    # plus a parent "Shared Drives (<ClientName>)" shortcut if multiple or as a quick root
    for idx, drive in enumerate(drives):
        drive_path = os.path.join(THINCLIENT_DIR, drive)
        href = f"file://{drive_path}"
        bm = ET.SubElement(root, "bookmark", {"href": href})
        title = ET.SubElement(bm, "title")
        title.text = format_drive_label(drive, client_name)
        info = ET.SubElement(bm, "info")
        meta_kde = ET.SubElement(info, "metadata", {"owner": "http://www.kde.org"})
        id_el = ET.SubElement(meta_kde, "ID")
        id_el.text = f"xrdp-drive-{idx}-{drive}"
        is_sys = ET.SubElement(meta_kde, "isSystemItem")
        is_sys.text = "false"
        meta_fd = ET.SubElement(info, "metadata", {"owner": "http://freedesktop.org"})
        ET.SubElement(meta_fd, "bookmark:icon", {"name": "drive-harddisk"})

    tmp_path = XBEL_PATH + ".tmp"
    tree.write(tmp_path, encoding="utf-8", xml_declaration=True)
    os.replace(tmp_path, XBEL_PATH)


def main() -> None:
    last_state = None
    while True:
        try:
            drives = get_redirected_drives()
            client_name = get_client_name() if drives else ""
            state = (tuple(drives), client_name)
            if state != last_state:
                sync_places(drives, client_name)
                last_state = state
        except Exception:
            pass
        time.sleep(3)


if __name__ == "__main__":
    main()

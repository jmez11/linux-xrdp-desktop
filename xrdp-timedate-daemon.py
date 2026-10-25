#!/usr/bin/env python3
"""
xrdp-timedate-daemon.py
Lightweight system D-Bus service implementing org.freedesktop.timedate1.
Allows KDE System Settings (Date & Time KCM) and timedatectl to inspect
and update system timezone inside a Docker container without full systemd.
"""
import os
import sys
import time
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

ZONEINFO_DIR = "/usr/share/zoneinfo"

def get_current_timezone():
    if os.path.exists("/etc/timezone"):
        try:
            with open("/etc/timezone", "r") as f:
                tz = f.read().strip()
                if tz and os.path.exists(os.path.join(ZONEINFO_DIR, tz)):
                    return tz
        except Exception:
            pass
    if os.path.islink("/etc/localtime"):
        try:
            target = os.path.realpath("/etc/localtime")
            prefix = ZONEINFO_DIR + "/"
            if target.startswith(prefix):
                return target[len(prefix):]
        except Exception:
            pass
    return "UTC"

class TimeDateService(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, "/org/freedesktop/timedate1")
        self.bus = bus
        self.timezone = get_current_timezone()

    @dbus.service.method(dbus_interface="org.freedesktop.DBus.Properties",
                         in_signature="ss", out_signature="v")
    def Get(self, interface_name, property_name):
        props = self.GetAll(interface_name)
        if property_name in props:
            return props[property_name]
        raise dbus.exceptions.DBusException(
            f"Property '{property_name}' not found",
            name="org.freedesktop.DBus.Error.UnknownProperty"
        )

    @dbus.service.method(dbus_interface="org.freedesktop.DBus.Properties",
                         in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name):
        if interface_name == "org.freedesktop.timedate1":
            self.timezone = get_current_timezone()
            now_usec = int(time.time() * 1000000)
            return {
                "Timezone": dbus.String(self.timezone),
                "LocalRTC": dbus.Boolean(False),
                "CanNTP": dbus.Boolean(False),
                "NTP": dbus.Boolean(False),
                "NTPSynchronized": dbus.Boolean(True),
                "TimeUSec": dbus.UInt64(now_usec),
                "RTCTimeUSec": dbus.UInt64(now_usec),
            }
        raise dbus.exceptions.DBusException(
            f"Interface '{interface_name}' not found",
            name="org.freedesktop.DBus.Error.UnknownInterface"
        )

    @dbus.service.method(dbus_interface="org.freedesktop.DBus.Properties",
                         in_signature="ssv", out_signature="")
    def Set(self, interface_name, property_name, new_value):
        pass

    @dbus.service.signal(dbus_interface="org.freedesktop.DBus.Properties",
                         signature="sa{sv}as")
    def PropertiesChanged(self, interface_name, changed_properties, invalidated_properties):
        pass

    @dbus.service.method(dbus_interface="org.freedesktop.timedate1",
                         in_signature="sb", out_signature="")
    def SetTimezone(self, timezone, interactive):
        tz = str(timezone).strip()
        tz_path = os.path.join(ZONEINFO_DIR, tz)
        if not os.path.exists(tz_path) or not tz:
            raise dbus.exceptions.DBusException(
                f"Invalid timezone: {tz}",
                name="org.freedesktop.timedate1.Error.InvalidTimezone"
            )

        # 1. Update /etc/localtime
        try:
            tmp_link = "/etc/localtime.tmp"
            if os.path.islink(tmp_link) or os.path.exists(tmp_link):
                os.remove(tmp_link)
            os.symlink(tz_path, tmp_link)
            os.replace(tmp_link, "/etc/localtime")
        except Exception:
            try:
                if os.path.islink("/etc/localtime") or os.path.exists("/etc/localtime"):
                    os.remove("/etc/localtime")
                os.symlink(tz_path, "/etc/localtime")
            except Exception:
                pass

        # 2. Update /etc/timezone
        try:
            with open("/etc/timezone", "w") as f:
                f.write(tz + "\n")
        except Exception:
            pass

        # 3. Update /etc/environment
        try:
            lines = []
            if os.path.exists("/etc/environment"):
                with open("/etc/environment", "r") as f:
                    lines = [l for l in f.readlines() if not l.startswith("TZ=")]
            lines.append(f"TZ={tz}\n")
            with open("/etc/environment", "w") as f:
                f.writelines(lines)
        except Exception:
            pass

        self.timezone = tz
        self.PropertiesChanged(
            "org.freedesktop.timedate1",
            {"Timezone": dbus.String(tz)},
            []
        )

    @dbus.service.method(dbus_interface="org.freedesktop.timedate1",
                         in_signature="bbb", out_signature="")
    def SetLocalRTC(self, local_rtc, fix_system, interactive):
        pass

    @dbus.service.method(dbus_interface="org.freedesktop.timedate1",
                         in_signature="bb", out_signature="")
    def SetNTP(self, use_ntp, interactive):
        pass

    @dbus.service.method(dbus_interface="org.freedesktop.timedate1",
                         in_signature="xbb", out_signature="")
    def SetTime(self, usec_utc, relative, interactive):
        pass

def main():
    DBusGMainLoop(set_as_default=True)
    try:
        bus = dbus.SystemBus()
    except Exception as e:
        sys.stderr.write(f"Failed to connect to system bus: {e}\n")
        sys.exit(1)

    bus_name = dbus.service.BusName("org.freedesktop.timedate1", bus)
    service = TimeDateService(bus)

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()

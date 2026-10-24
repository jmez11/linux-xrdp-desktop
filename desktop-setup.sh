#!/bin/bash
# One-time KDE Plasma macOS-style desktop setup for the XRDP container.
# Configures:
#   1. Smooth subpixel font rendering (Inter + Fira Code, RGB anti-aliasing,
#      slight hinting, 96 DPI) across Qt/KDE, GTK, and X11.
#   2. Top Menu Bar (User Switcher, Window Title, Global Menu, Spacer,
#      System Tray, Control Centre, Digital Clock).
#   3. Bottom animated Dock (hover zoom/bounce via Task.qml) with native Dolphin
#      icon, Mkos-Big-Sur icons for other apps, and working launchers for
#      preinstalled apps (Dolphin, Firefox, VS Code, Konsole, Kate, Gwenview,
#      Okular, GIMP, Inkscape, Blender, VLC, LibreOffice Calc/Writer,
#      Calculator, System Settings) + Disks & Devices + Trash.
#   4. Desktop top-left rounded widgets:
#      - Calendar widget (top-left)
#      - Weather widget (next to Calendar, IP-geolocated)
#      - Analog Clock widget (below Calendar)
#   5. Desktop top-right automatic icon layout (Columns + Right alignment) with
#      "System Drive" hard drive icon at top-right.
#   6. Automatic one-click .deb package installation via xrdp-deb-installer.desktop.
#   7. Left-aligned traffic-light window controls (Summaculate Aurorae, XIA).
set -u

SENTINEL="$HOME/.config/xrdp-kde-macos-setup-v4.done"
[ -f "$SENTINEL" ] && exit 0

WALLPAPER="/usr/share/backgrounds/xrdp-wow.jpg"
mkdir -p "$HOME/.config" "$HOME/.local/share/konsole" "$HOME/.local/share/applications" "$HOME/Desktop"

# ---------------------------------------------------------------------------
# 1. Smooth Font Rendering (Qt/KDE, Fontconfig, Xft, GTK)
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/fontconfig"
cat << 'EOF' > "$HOME/.config/fontconfig/fonts.conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>
  </match>
</fontconfig>
EOF

cat << 'EOF' > "$HOME/.Xresources"
Xft.antialias: 1
Xft.hinting: 1
Xft.hintstyle: hintslight
Xft.rgba: rgb
Xft.lcdfilter: lcddefault
Xft.dpi: 96
EOF
xrdb -merge "$HOME/.Xresources" 2>/dev/null || true

kwriteconfig5 --file kdeglobals --group General --key XftAntialias "true"
kwriteconfig5 --file kdeglobals --group General --key XftHintStyle "hintslight"
kwriteconfig5 --file kdeglobals --group General --key XftSubPixel "rgb"
kwriteconfig5 --file kdeglobals --group General --key font "Inter,10,-1,5,50,0,0,0,0,0,Regular"
kwriteconfig5 --file kdeglobals --group General --key fixed "Fira Code,10,-1,5,50,0,0,0,0,0,Regular"
kwriteconfig5 --file kdeglobals --group General --key smallestReadableFont "Inter,8,-1,5,50,0,0,0,0,0,Regular"
kwriteconfig5 --file kdeglobals --group General --key toolBarFont "Inter,10,-1,5,50,0,0,0,0,0,Regular"
kwriteconfig5 --file kdeglobals --group General --key menuFont "Inter,10,-1,5,50,0,0,0,0,0,Regular"
kwriteconfig5 --file kdeglobals --group WM --key activeFont "Inter,10,-1,5,75,0,0,0,0,0,Bold"
kwriteconfig5 --file kcmfonts --group General --key forceFontDPI "96"

# ---------------------------------------------------------------------------
# 2. Theme, Mkos-Big-Sur Icons (preserving native Dolphin icon), and GTK Sync
# ---------------------------------------------------------------------------
kwriteconfig5 --file kdeglobals --group General --key ColorScheme "BreezeDark"
kwriteconfig5 --file kdeglobals --group KDE --key LookAndFeelPackage "org.kde.breezedark.desktop"
kwriteconfig5 --file kdeglobals --group KDE --key widgetStyle "Breeze"
kwriteconfig5 --file kdeglobals --group Icons --key Theme "Mkos-Big-Sur"
kwriteconfig5 --file kdeglobals --group KDE --key SingleClick "false"
kwriteconfig5 --file kdeglobals --group WM --key activeBackground "30,30,46"
kwriteconfig5 --file kdeglobals --group WM --key activeForeground "205,214,244"
kwriteconfig5 --file kdeglobals --group WM --key inactiveBackground "24,24,37"
kwriteconfig5 --file kdeglobals --group WM --key inactiveForeground "166,173,200"

mkdir -p "$HOME/.config/gtk-3.0"
cat << 'EOF' > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Breeze-Dark
gtk-icon-theme-name=Mkos-Big-Sur
gtk-font-name=Inter 10
gtk-application-prefer-dark-theme=true
gtk-decoration-layout=close,minimize,maximize:
gtk-modules=appmenu-gtk-module
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
EOF

# Associate .deb files with the automatic package installer
cat << 'EOF' > "$HOME/.config/mimeapps.list"
[Default Applications]
application/vnd.debian.binary-package=xrdp-deb-installer.desktop
application/x-deb=xrdp-deb-installer.desktop
application/x-debian-package=xrdp-deb-installer.desktop

[Added Associations]
application/vnd.debian.binary-package=xrdp-deb-installer.desktop;
application/x-deb=xrdp-deb-installer.desktop;
application/x-debian-package=xrdp-deb-installer.desktop;
EOF

# ---------------------------------------------------------------------------
# 3. Clean up any user-local code.desktop override & Create "System Drive" Icon
# ---------------------------------------------------------------------------
rm -f "$HOME/.local/share/applications/code.desktop"
if [ -f /usr/share/applications/code.desktop ]; then
    cp /usr/share/applications/code.desktop "$HOME/.local/share/applications/vscode.desktop"
    chmod +x "$HOME/.local/share/applications/vscode.desktop"
fi
kbuildsycoca5 --noincremental >/dev/null 2>&1 || kbuildsycoca5 >/dev/null 2>&1 || true

# Remove old "Macintosh HD" or legacy desktop icons and create "System Drive"
rm -f "$HOME/Desktop/Macintosh HD.desktop" "$HOME/Desktop/Trash.desktop" "$HOME/Desktop/Home.desktop"
cat << 'EOF' > "$HOME/Desktop/System Drive.desktop"
[Desktop Entry]
Type=Link
Name=System Drive
Icon=drive-harddisk-system
URL=file:///
EOF
chmod +x "$HOME/Desktop/System Drive.desktop"
gio set "$HOME/Desktop/System Drive.desktop" metadata::trusted true 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Window Decorations & Left-Side Traffic Light Buttons
# ---------------------------------------------------------------------------
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key library "org.kde.kwin.aurorae"
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__summaculate-night-opaque"
kwriteconfig5 --file kwinrc --group kwinrc --key BorderlessMaximizedWindows "false"
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "XIA"
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key BorderSize "None"
kwriteconfig5 --file kwinrc --group Compositing --key Enabled "false"
kwriteconfig5 --file kwinrc --group Compositing --key OpenGLIsUnsafe "false"
kwriteconfig5 --file kwinrc --group ElectricBorders --key TopLeft "Overview"

kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock "false"
kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume "false"

cat << 'EOF' > "$HOME/.local/share/konsole/macOS.profile"
[Appearance]
ColorScheme=Breeze
Font=Fira Code,11,-1,5,50,0,0,0,0,0
AntiAliasFonts=true

[General]
Name=macOS
Parent=FALLBACK/
EOF
kwriteconfig5 --file konsolerc --group "Desktop Entry" --key DefaultProfile "macOS.profile"

# ---------------------------------------------------------------------------
# 5. Wait for plasmashell DBus interface to become ready
# ---------------------------------------------------------------------------
for _ in $(seq 1 25); do
    if qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ---------------------------------------------------------------------------
# 6. Apply Two-Panel Layout + Desktop Widgets + Top-Right Hard Drive Layout
# ---------------------------------------------------------------------------
JS_SCRIPT=$(cat << 'EOF'
// Remove existing panels so we build a clean two-panel layout
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// -------------------------------------------------------------------------
// Top Panel -> Menu Bar
// Order: User Switcher, Window Title, Global Menu, Spacer, System Tray,
//        Control Hub (Control Centre), Digital Clock
// -------------------------------------------------------------------------
var topPanel = new Panel("org.kde.panel");
topPanel.location = "top";
topPanel.height = 28;
topPanel.floating = false;
topPanel.opacity = "translucent";
topPanel.hiding = "none";

var userSwitcher = topPanel.addWidget("org.kde.plasma.userswitcher");
userSwitcher.currentConfigGroup = ["General"];
userSwitcher.writeConfig("showFace", true);
userSwitcher.writeConfig("showName", false);
userSwitcher.writeConfig("showFullName", false);

var winTitle = topPanel.addWidget("org.kde.windowtitle");
winTitle.currentConfigGroup = ["General"];
winTitle.writeConfig("style", 0);
winTitle.writeConfig("boldFont", true);
winTitle.writeConfig("showIcon", false);
winTitle.writeConfig("placeHolder", "");
winTitle.writeConfig("filterActivityInfo", false);

var appMenu = topPanel.addWidget("org.kde.plasma.appmenu");

var spacer = topPanel.addWidget("org.kde.plasma.panelspacer");
spacer.currentConfigGroup = ["General"];
spacer.writeConfig("expanding", true);

var sysTray = topPanel.addWidget("org.kde.plasma.systemtray");
var sysTrayContainment = sysTray.readConfig("SystrayContainmentId", "");
if (sysTrayContainment) {
    var tray = desktopById(sysTrayContainment);
    if (tray) {
        tray.currentConfigGroup = ["General"];
        tray.writeConfig("shownItems", [
            "org.kde.plasma.volume",
            "org.kde.plasma.networkmanagement",
            "org.kde.plasma.battery",
            "org.kde.plasma.mediacontroller"
        ]);
    }
}

var controlHub = topPanel.addWidget("com.github.prayag2.controlcentre");
controlHub.currentConfigGroup = ["Appearance"];
controlHub.writeConfig("isDarkTheme", true);
controlHub.writeConfig("transparency", true);

var clock = topPanel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", "BesideTime");
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd MMM d");
clock.writeConfig("use24hFormat", 0);

// -------------------------------------------------------------------------
// Desktop Containments:
//   - Automatic icon layout to Top-Right (arrangement = 1 [Columns],
//     alignment = 1 [Right], sortMode = 1 [Name]) so "System Drive" sits at
//     top-right
//   - Top-Left Desktop Widgets: Calendar, Weather (IP-geolocated), Analog Clock
//     with macOS widget padding matching the reference screenshot
//   - Bottom-Center Animated macOS Dock (org.macos.desktop.dock) with unclipped
//     parabolic magnification and multi-bounce launch animation
// -------------------------------------------------------------------------
var allDesktops = desktops();
for (var d = 0; d < allDesktops.length; d++) {
    var desk = allDesktops[d];
    desk.wallpaperPlugin = "org.kde.image";
    desk.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desk.writeConfig("Image", "file:///usr/share/backgrounds/xrdp-wow.jpg");

    desk.currentConfigGroup = ["General"];
    desk.writeConfig("arrangement", 1); // Columns (top-to-bottom)
    desk.writeConfig("alignment", 1);   // Right side of screen (top-right start)
    desk.writeConfig("sortMode", 1);    // Sort by Name
    desk.writeConfig("iconSize", 3);    // 64px desktop drive icon
    desk.writeConfig("labelMode", 0);
    desk.writeConfig("toolTips", true);

    if (d === 0) {
        var oldWidgets = desk.widgets();
        for (var w = 0; w < oldWidgets.length; w++) {
            oldWidgets[w].remove();
        }
        var calW = desk.addWidget("org.macos.desktop.calendar");
        var weaW = desk.addWidget("org.macos.desktop.weather");
        var clkW = desk.addWidget("org.macos.desktop.clock");
        var dockW = desk.addWidget("org.macos.desktop.dock");

        function makeGeom(scrW, scrH) {
            var dockWidth = Math.min(1120, scrW - 32);
            var dockX = Math.max(16, Math.round((scrW - dockWidth) / 2));
            var dockY = Math.max(420, scrH - 122);
            return "Applet-" + calW.id + ":16,38,184,184,0;" +
                   "Applet-" + weaW.id + ":204,38,184,184,0;" +
                   "Applet-" + clkW.id + ":16,226,184,184,0;" +
                   "Applet-" + dockW.id + ":" + dockX + "," + dockY + "," + dockWidth + ",116,0;";
        }

        var curG = screenGeometry(desk.screen);
        var curW = (curG && curG.width > 0) ? curG.width : 1920;
        var curH = (curG && curG.height > 0) ? curG.height : 1080;

        desk.writeConfig("ItemGeometriesHorizontal", makeGeom(curW, curH));
        desk.writeConfig("ItemGeometries-" + curW + "x" + curH, makeGeom(curW, curH));
        desk.writeConfig("ItemGeometries-1920x1080", makeGeom(1920, 1080));
        desk.writeConfig("ItemGeometries-2560x1440", makeGeom(2560, 1440));
        desk.writeConfig("ItemGeometries-1600x900", makeGeom(1600, 900));
        desk.writeConfig("ItemGeometries-1366x768", makeGeom(1366, 768));
    }
}
EOF
)

qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$JS_SCRIPT" >/dev/null 2>&1 || true

# Ensure the bottom dock panel has lengthMode=fit ("Fill Content") in plasmashellrc
if [ -f "$HOME/.config/plasmashellrc" ]; then
    sed -i '/\[PlasmaViews\]\[Panel /,/^\s*$/{s/alignment=132/alignment=132\nlengthMode=fit/}' "$HOME/.config/plasmashellrc" 2>/dev/null || true
fi

# Reload KWin & Plasma settings so fonts, decorations, and icons apply immediately
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
/usr/lib/x86_64-linux-gnu/libexec/plasma-changeicons Mkos-Big-Sur >/dev/null 2>&1 || true

# Restart plasmashell cleanly once so Folder View picks up Right/Column icon alignment
# and exact top-left widget geometries from plasma-org.kde.plasma.desktop-appletsrc
kquitapp5 plasmashell >/dev/null 2>&1 || killall plasmashell 2>/dev/null || true
sleep 1
kstart5 plasmashell >/dev/null 2>&1 || plasmashell >/dev/null 2>&1 &

touch "$SENTINEL"

exit 0

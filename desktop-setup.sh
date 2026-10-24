#!/bin/bash
# One-time KDE Plasma macOS-style desktop setup for the XRDP container.
# Implements the How-To Geek "Here's How I Made Linux Feel More Like macOS
# Using KDE Plasma" customization steps:
#   Step 1: Two-panel layout (top Menu Bar + bottom Dock)
#   Step 2: Bottom panel Dock (Icons-Only Task Manager + Disks & Devices,
#           Fill Content width, Dodge Windows visibility, 48px macOS Dock size,
#           pinned default apps)
#   Step 3: Top panel Menu Bar (User Switcher showing User Picture, Window Title
#           bold with %a app name and hidden icon, Global Menu, flexible Spacer,
#           System Tray with Audio/Network/Media always shown, Control Hub /
#           Control Centre, Digital Clock with date always beside time 'MMM dd',
#           translucent opacity, non-floating)
#   Step 4: Mkos-Big-Sur macOS icon pack + Summaculate Aurorae traffic-light
#           window decorations
#   Step 5: Window titlebar buttons moved to the left in macOS order (XIA: Close,
#           Minimize, Maximize)
set -u

SENTINEL="$HOME/.config/xrdp-kde-macos-setup-v1.done"
[ -f "$SENTINEL" ] && exit 0

WALLPAPER="/usr/share/backgrounds/xrdp-wow.jpg"
mkdir -p "$HOME/.config" "$HOME/.local/share/konsole"

# ---------------------------------------------------------------------------
# 1. Theme, Icons (Step 4: Mkos-Big-Sur), Dark Color Scheme, and Fonts
# ---------------------------------------------------------------------------
kwriteconfig5 --file kdeglobals --group General --key ColorScheme "BreezeDark"
kwriteconfig5 --file kdeglobals --group KDE --key LookAndFeelPackage "org.kde.breezedark.desktop"
kwriteconfig5 --file kdeglobals --group KDE --key widgetStyle "Breeze"
kwriteconfig5 --file kdeglobals --group Icons --key Theme "Mkos-Big-Sur"
kwriteconfig5 --file kdeglobals --group General --key font "Inter,10,-1,5,50,0,0,0,0,0"
kwriteconfig5 --file kdeglobals --group General --key fixed "Fira Code,10,-1,5,50,0,0,0,0,0"
kwriteconfig5 --file kdeglobals --group WM --key activeBackground "30,30,46"
kwriteconfig5 --file kdeglobals --group WM --key activeForeground "205,214,244"
kwriteconfig5 --file kdeglobals --group WM --key inactiveBackground "24,24,37"
kwriteconfig5 --file kdeglobals --group WM --key inactiveForeground "166,173,200"

# Sync GTK3/GTK2 apps with Mkos-Big-Sur icons and left-side macOS buttons
mkdir -p "$HOME/.config/gtk-3.0"
cat << 'EOF' > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Breeze-Dark
gtk-icon-theme-name=Mkos-Big-Sur
gtk-font-name=Inter 10
gtk-application-prefer-dark-theme=true
gtk-decoration-layout=close,minimize,maximize:
gtk-modules=appmenu-gtk-module
EOF

# ---------------------------------------------------------------------------
# 2. Window Decorations & Left-Side Traffic Light Buttons (Steps 4 & 5)
#    - Summaculate Night Opaque Aurorae decoration by doncsugar
#    - ButtonsOnLeft=XIA (Close, Minimize, Maximize on the left)
#    - ButtonsOnRight="" (no buttons on the right)
#    - Compositor disabled over RDP to avoid software-compositing drag lag
# ---------------------------------------------------------------------------
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key library "org.kde.kwin.aurorae"
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__summaculate-night-opaque"
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "XIA"
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key BorderSize "None"
kwriteconfig5 --file kwinrc --group Compositing --key Enabled "false"
kwriteconfig5 --file kwinrc --group Compositing --key OpenGLIsUnsafe "false"

# Enable KRunner on Alt+Space (macOS Spotlight feel) and top-left Hot Corner Overview
kwriteconfig5 --file kwinrc --group ElectricBorders --key TopLeft "Overview"

# Disable screen locker inside RDP container
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock "false"
kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume "false"

# Konsole profile with Fira Code font
cat << 'EOF' > "$HOME/.local/share/konsole/macOS.profile"
[Appearance]
ColorScheme=Breeze
Font=Fira Code,11,-1,5,50,0,0,0,0,0

[General]
Name=macOS
Parent=FALLBACK/
EOF
kwriteconfig5 --file konsolerc --group "Desktop Entry" --key DefaultProfile "macOS.profile"

# ---------------------------------------------------------------------------
# 3. Wait for plasmashell DBus interface to become ready
# ---------------------------------------------------------------------------
for _ in $(seq 1 25); do
    if qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ---------------------------------------------------------------------------
# 4. Apply Two-Panel macOS Layout (Steps 1, 2, 3) + Wallpaper via Plasma JS API
# ---------------------------------------------------------------------------
JS_SCRIPT=$(cat << 'EOF'
// Remove existing panels so we build a clean macOS two-panel layout
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// -------------------------------------------------------------------------
// Step 3: Top Panel -> macOS Menu Bar
// Order: User Switcher, Window Title, Global Menu, Spacer, System Tray,
//        Control Hub (Control Centre), Digital Clock
// -------------------------------------------------------------------------
var topPanel = new Panel("org.kde.panel");
topPanel.location = "top";
topPanel.height = 28;
topPanel.floating = false;
topPanel.opacity = "translucent";
topPanel.hiding = "none";

// 1. User Switcher (Apple Menu equivalent -> Show only User Picture)
var userSwitcher = topPanel.addWidget("org.kde.plasma.userswitcher");
userSwitcher.currentConfigGroup = ["General"];
userSwitcher.writeConfig("showFace", true);
userSwitcher.writeConfig("showName", false);
userSwitcher.writeConfig("showFullName", false);

// 2. Window Title (Bold active app name %a, no icon, blank when unavailable)
var winTitle = topPanel.addWidget("org.kde.windowtitle");
winTitle.currentConfigGroup = ["General"];
winTitle.writeConfig("style", 0);
winTitle.writeConfig("boldFont", true);
winTitle.writeConfig("showIcon", false);
winTitle.writeConfig("placeHolder", "");
winTitle.writeConfig("filterActivityInfo", false);

// 3. Global Menu (Application Menu Bar)
var appMenu = topPanel.addWidget("org.kde.plasma.appmenu");

// 4. Flexible Spacer between Global Menu and right-side status items
var spacer = topPanel.addWidget("org.kde.plasma.panelspacer");
spacer.currentConfigGroup = ["General"];
spacer.writeConfig("expanding", true);

// 5. System Tray (Audio Volume, Network, Power/Battery, Media Player always shown)
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
            "org.kde.plasma.mediacontroller",
            "org.kde.plasma.weather"
        ]);
    }
}

// 6. Control Hub / Control Centre (macOS Control Center equivalent)
var controlHub = topPanel.addWidget("com.github.prayag2.controlcentre");
controlHub.currentConfigGroup = ["Appearance"];
controlHub.writeConfig("isDarkTheme", true);
controlHub.writeConfig("transparency", true);

// 7. Digital Clock (Date always beside time, custom format 'MMM dd')
var clock = topPanel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", "BesideTime");
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "MMM dd");
clock.writeConfig("use24hFormat", 0);

// -------------------------------------------------------------------------
// Step 2: Bottom Panel -> macOS Dock
// Widgets: Icons-Only Task Manager + Disks & Devices
// Settings: Width = Fill Content (lengthMode = fit), Visibility = Dodge
//           Windows (windowsgobelow), Height = 48 units
// -------------------------------------------------------------------------
var dock = new Panel("org.kde.panel");
dock.location = "bottom";
dock.height = 48;
dock.alignment = "center";
dock.hiding = "windowsgobelow";
dock.floating = true;

// Shrink panel width to fit icons ("Fill Content")
var screenW = screenGeometry(dock.screen).width;
if (screenW > 0) {
    dock.minimumLength = 120;
    dock.maximumLength = screenW;
}

var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop",
    "applications:code.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:vlc.desktop",
    "applications:gimp.desktop",
    "applications:systemsettings.desktop"
]);
tasks.writeConfig("showOnlyCurrentScreen", false);
tasks.writeConfig("maxStripes", 1);

var disks = dock.addWidget("org.kde.plasma.devicenotifier");

// Set wallpaper on all desktops
var allDesktops = desktops();
for (var d = 0; d < allDesktops.length; d++) {
    var desk = allDesktops[d];
    desk.wallpaperPlugin = "org.kde.image";
    desk.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desk.writeConfig("Image", "file:///usr/share/backgrounds/xrdp-wow.jpg");
}
EOF
)

qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$JS_SCRIPT" >/dev/null 2>&1 || true

# Ensure the bottom dock panel has lengthMode=fit ("Fill Content") in plasmashellrc
if [ -f "$HOME/.config/plasmashellrc" ]; then
    sed -i '/\[PlasmaViews\]\[Panel /,/^\s*$/{s/alignment=132/alignment=132\nlengthMode=fit/}' "$HOME/.config/plasmashellrc" 2>/dev/null || true
fi

# Reload KWin so Summaculate left-side traffic-light window buttons & theme apply immediately
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
/usr/lib/x86_64-linux-gnu/libexec/plasma-changeicons Mkos-Big-Sur >/dev/null 2>&1 || true

touch "$SENTINEL"

# First-login wow: Konsole with system info
if command -v konsole >/dev/null 2>&1 && command -v neofetch >/dev/null 2>&1; then
    konsole -e bash -c "neofetch; exec bash" &
fi

exit 0

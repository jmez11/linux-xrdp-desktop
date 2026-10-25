FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Desktop environment (KDE Plasma) and GPU/Hardware acceleration packages
#    Notes: libgl1-mesa-glx is not shipped in Ubuntu 24.04 (superseded by libgl1);
#    pulseaudio-module-xrdp is not packaged in 24.04 either and is built from
#    source in step 3 below; xrdp/xorgxrdp are built from source with x264 and
#    [MS-RDPECAM] in step 1b (Ubuntu's xrdp 0.9.24 has no H.264 support at all),
#    so xserver-xorg-core (pulled in by xorgxrdp's apt package) and libx264-164
#    (the encoder runtime) are installed explicitly here.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xserver-xorg-core \
    libx264-164 \
    libfuse3-3 \
    fuse3 \
    libopus0 \
    plasma-desktop \
    plasma-workspace \
    plasma-widgets-addons \
    plasma-pa \
    plasma-nm \
    kdeconnect \
    kwin-x11 \
    kde-cli-tools \
    kde-style-breeze \
    breeze \
    breeze-icon-theme \
    breeze-cursor-theme \
    breeze-gtk-theme \
    kde-config-gtk-style \
    systemsettings \
    konsole \
    dolphin \
    kate \
    ark \
    gwenview \
    okular \
    kde-spectacle \
    kcalc \
    kdialog \
    libnotify-bin \
    desktop-file-utils \
    libdbusmenu-glib4 \
    libdbusmenu-gtk3-4 \
    libdbusmenu-qt5-2 \
    qml-module-qtgraphicaleffects \
    qml-module-qtquick-controls2 \
    qml-module-qtquick-layouts \
    qml-module-org-kde-bluezqt \
    qml-module-org-kde-kquickcontrolsaddons \
    libqt5svg5 \
    x11-xserver-utils \
    xfonts-base \
    dbus-x11 \
    accountsservice \
    polkitd \
    pkexec \
    polkit-kde-agent-1 \
    sudo \
    curl \
    openssl \
    ca-certificates \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    intel-media-va-driver \
    intel-opencl-icd \
    libze1 \
    libze-intel-gpu1 \
    clinfo \
    mesa-utils \
    vainfo \
    vulkan-tools \
    libgl1-mesa-dri \
    libvulkan1 \
    libxv1 \
    libglu1-mesa \
    libegl1 \
    libgl1 \
    pulseaudio \
    pulseaudio-utils \
    pavucontrol \
    alsa-utils \
    libopenh264-7 \
    pipewire \
    pipewire-bin \
    libpipewire-0.3-0t64 \
    libpipewire-0.3-modules \
    pipewire-v4l2 \
    wireplumber \
    xdg-desktop-portal \
    xdg-desktop-portal-kde \
    xdg-desktop-portal-gtk \
    v4l-utils \
    gstreamer1.0-pipewire \
    gnupg \
    git \
    htop \
    neofetch \
    python3 \
    python3-dbus \
    python3-gi \
    tzdata \
    cairo-dock \
    cairo-dock-plug-ins \
    fonts-firacode \
    fonts-inter \
    fonts-noto-core \
    fonts-noto-color-emoji \
    fonts-liberation2 \
    fontconfig \
    gimp \
    inkscape \
    vlc \
    libreoffice \
    glmark2-x11 \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# 1b. Build xrdp 0.10.3 + xorgxrdp 0.10.3 from source with x264 H.264 encoding
#     and [MS-RDPECAM] PipeWire camera redirection (--enable-rdpecam).
#     This is the fix for choppy video and laggy window drags: H.264 is a real
#     video codec with temporal compression, while RFX (all Ubuntu's xrdp 0.9.24
#     offers) re-encodes every frame as a still image. Configure flags mirror
#     Ubuntu's own xrdp build (debian/rules from xrdp_0.9.24-4) plus --enable-x264
#     and --enable-rdpecam.
#     Installed to distro paths (/usr/sbin, /etc/xrdp) so the config steps below
#     and the entrypoint keep working unchanged. Build deps are purged in-layer.
COPY xrdp-rdpecam /tmp/xrdp-rdpecam
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config nasm patch \
        libx264-dev libfuse3-dev libjpeg-dev libopus-dev libpam0g-dev libssl-dev \
        libx11-dev libxfixes-dev libxrandr-dev \
        xserver-xorg-dev libgbm-dev libepoxy-dev libegl1-mesa-dev \
        libpipewire-0.3-dev libopenh264-dev \
    && mkdir -p /tmp/xrdp-build && cd /tmp/xrdp-build \
    && curl -fsSL -o xrdp.tar.gz https://github.com/neutrinolabs/xrdp/releases/download/v0.10.3/xrdp-0.10.3.tar.gz \
    && tar xzf xrdp.tar.gz && cd xrdp-0.10.3 \
    && cp /tmp/xrdp-rdpecam/rdpecam.c /tmp/xrdp-rdpecam/rdpecam.h \
          /tmp/xrdp-rdpecam/rdpecam_pipewire.c /tmp/xrdp-rdpecam/rdpecam_pipewire.h \
          sesman/chansrv/ \
    && patch -p1 < /tmp/xrdp-rdpecam/xrdp-0.10.3-rdpecam.patch \
    && ./bootstrap \
    && ./configure \
        --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
        --with-socketdir=/run/xrdp/sockdir \
        --enable-ipv6 --enable-jpeg --enable-fuse --enable-rfxcodec \
        --enable-opus --enable-painter --enable-vsock --enable-x264 \
        --enable-rdpecam \
    && make -j"$(nproc)" && make install \
    && cd /tmp/xrdp-build \
    && curl -fsSL -o xorgxrdp.tar.gz https://github.com/neutrinolabs/xorgxrdp/archive/refs/tags/v0.10.3.tar.gz \
    && tar xzf xorgxrdp.tar.gz && cd xorgxrdp-0.10.3 \
    && ./bootstrap && ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    && make -j"$(nproc)" && make install \
    && ldd /usr/sbin/xrdp | grep -q libx264 \
    && ldd /usr/sbin/xrdp-chansrv | grep -q libpipewire \
    && ldd /usr/sbin/xrdp-chansrv | grep -q libopenh264 \
    && cd / && rm -rf /tmp/xrdp-build /tmp/xrdp-rdpecam \
    && apt-get purge -y build-essential autoconf automake libtool pkg-config nasm patch \
        libx264-dev libfuse3-dev libjpeg-dev libopus-dev libpam0g-dev libssl-dev \
        libx11-dev libxfixes-dev libxrandr-dev \
        xserver-xorg-dev libgbm-dev libepoxy-dev libegl1-mesa-dev \
        libpipewire-0.3-dev libopenh264-dev \
    && apt-get autoremove -y --purge \
    && rm -rf /var/lib/apt/lists/* \
    && if ldd /usr/sbin/xrdp /usr/sbin/xrdp-sesman /usr/sbin/xrdp-chansrv /usr/libexec/xrdp/xrdp-sesexec 2>/dev/null | grep -q "not found"; then echo "FATAL: xrdp binaries have missing shared libraries"; ldd /usr/sbin/xrdp-chansrv | grep "not found"; exit 1; fi

# 2. Third-party apps via their own APT repos (Ubuntu's firefox/chromium are
#    snaps, which don't work in containers): Firefox (Mozilla) and VS Code.
RUN install -d -m 0755 /etc/apt/keyrings && \
    curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
        -o /etc/apt/keyrings/packages.mozilla.org.asc && \
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
        > /etc/apt/sources.list.d/mozilla.list && \
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        > /etc/apt/preferences.d/mozilla && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        > /etc/apt/sources.list.d/vscode.list \
    && apt-get update && apt-get install -y --no-install-recommends firefox code \
    && if [ -f /usr/share/code/code ] && [ ! -f /usr/share/code/code.real ]; then mv /usr/share/code/code /usr/share/code/code.real; fi \
    && rm -rf /var/lib/apt/lists/*

# 3. Build pulseaudio-module-xrdp from source (neutrinolabs, v0.8).
#    Ubuntu 24.04 does not package the XRDP PulseAudio modules, and they must be
#    compiled against this release's exact PulseAudio sources (internal module API).
#    Build dependencies are purged in the same layer so the final image stays lean.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf libtool pkg-config meson ninja-build libpulse-dev \
    && sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && apt-get build-dep -y pulseaudio \
    && mkdir -p /tmp/pa-build && cd /tmp/pa-build && apt-get source pulseaudio \
    && PA_SRC="$(find /tmp/pa-build -maxdepth 1 -type d -name 'pulseaudio-[0-9]*' | head -1)" \
    && cd "$PA_SRC" && ( [ -x ./configure ] && ./configure || meson setup build ) \
    && git clone --depth 1 --branch v0.8 https://github.com/neutrinolabs/pulseaudio-module-xrdp.git /tmp/pa-build/pa-module-xrdp \
    && cd /tmp/pa-build/pa-module-xrdp && ./bootstrap && ./configure PULSE_DIR="$PA_SRC" && make && make install \
    && ls "$(pkg-config --variable=modlibexecdir libpulse)" | grep -q xrdp \
    && cd / && rm -rf /tmp/pa-build \
    && apt-get purge -y build-essential autoconf libtool pkg-config meson ninja-build libpulse-dev \
    && apt-get autoremove -y --purge \
    && rm -rf /var/lib/apt/lists/*

# 4. Install VirtualGL for headless 3D/OpenGL hardware offloading
RUN VGL_VER="3.1.1" \
    && curl -fsSL -o /tmp/virtualgl.deb \
       "https://github.com/VirtualGL/virtualgl/releases/download/${VGL_VER}/virtualgl_${VGL_VER}_amd64.deb" \
    && dpkg -i /tmp/virtualgl.deb \
    && rm -f /tmp/virtualgl.deb

# 5. Configure Xorg permissions for non-root execution inside container
RUN sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config 2>/dev/null || \
    echo "allowed_users=anybody" >> /etc/X11/Xwrapper.config && \
    echo "needs_root_rights=no" >> /etc/X11/Xwrapper.config

# 6. Configure XRDP for Credential Pass-Through, TLS, and Multi-Monitor
RUN sed -i 's/^autorun=.*/autorun=Xorg/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^#require_credentials=true/require_credentials=true/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^allow_multimon=false/allow_multimon=true/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^security_layer=negotiate/security_layer=tls/' /etc/xrdp/xrdp.ini

# 7. Configure PulseAudio daemon, XRDP audio sinks, and PipeWire/Firefox camera redirection
#    PulseAudio handles RDP audio (module-xrdp-sink/source); WirePlumber's ALSA
#    audio monitor is disabled so PipeWire only manages Video/Source camera nodes
#    published by xrdp-chansrv ([MS-RDPECAM]). Firefox's PipeWire camera backend
#    is enabled by default via system policy/pref.
RUN sed -i 's/^; exit-idle-time = 20/exit-idle-time = -1/' /etc/pulse/daemon.conf && \
    sed -i 's/^; autospawn = yes/autospawn = yes/' /etc/pulse/client.conf && \
    echo "load-module module-xrdp-sink" >> /etc/pulse/default.pa && \
    echo "load-module module-xrdp-source" >> /etc/pulse/default.pa && \
    mkdir -p /etc/wireplumber/main.lua.d /etc/wireplumber/wireplumber.conf.d && \
    printf 'alsa_monitor.enabled = false\n' > /etc/wireplumber/main.lua.d/90-xrdp-disable-alsa.lua && \
    printf 'wireplumber.profiles = {\n  main = {\n    monitor.alsa = disabled\n  }\n}\n' > /etc/wireplumber/wireplumber.conf.d/90-xrdp-disable-alsa.conf && \
    mkdir -p /etc/firefox/pref /usr/lib/firefox/distribution && \
    printf 'pref("media.webrtc.camera.allow-pipewire", true);\n' > /etc/firefox/pref/xrdp-camera.js && \
    printf '{\n  "policies": {\n    "Preferences": {\n      "media.webrtc.camera.allow-pipewire": {\n        "Value": true,\n        "Status": "default"\n      }\n    }\n  }\n}\n' > /usr/lib/firefox/distribution/policies.json

# 8. Generate TLS Certificate
RUN openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem \
    -days 3650 -subj "/CN=rdp-container" && \
    chown root:root /etc/xrdp/key.pem /etc/xrdp/cert.pem && \
    chmod 600 /etc/xrdp/key.pem

# 9. Desktop wow factor: macOS-style KDE Plasma assets (How-To Geek guide):
#    - Mkos-Big-Sur icon theme (zayronxio/Mkos-Big-Sur)
#    - Summaculate Aurorae window decorations (doncsugar/sumac-theme)
#    - Window Title applet (org.kde.windowtitle)
#    - Control Centre / Control Hub applet (EliverLara/kde-control-station)
#    - Wallpaper + first-run KDE Plasma macOS layout & appearance setup script
RUN mkdir -p /usr/share/icons /usr/share/aurorae/themes /usr/share/plasma/plasmoids \
    && git clone --depth 1 https://github.com/zayronxio/Mkos-Big-Sur.git /usr/share/icons/Mkos-Big-Sur \
    && rm -rf /usr/share/icons/Mkos-Big-Sur/.git /usr/share/icons/Mkos-Big-Sur/preview-icons-apps \
    && rm -f /usr/share/icons/Mkos-Big-Sur/*/apps/*dolphin*.svg /usr/share/icons/Mkos-Big-Sur/*/apps/*file-manager*.svg /usr/share/icons/Mkos-Big-Sur/*/apps/Filemanager.svg \
    && gtk-update-icon-cache -f /usr/share/icons/Mkos-Big-Sur 2>/dev/null || true \
    && git clone --depth 1 https://github.com/doncsugar/sumac-theme.git /tmp/sumac-theme \
    && cp -r /tmp/sumac-theme/aurorae/summaculate/* /usr/share/aurorae/themes/ \
    && cp -r /tmp/sumac-theme/aurorae/sumac/* /usr/share/aurorae/themes/ \
    && rm -rf /tmp/sumac-theme \
    && git clone --depth 1 https://github.com/psifidotos/applet-window-title.git /usr/share/plasma/plasmoids/org.kde.windowtitle \
    && rm -rf /usr/share/plasma/plasmoids/org.kde.windowtitle/.git \
    && git clone --depth 1 https://github.com/EliverLara/kde-control-station.git /tmp/kde-control-station \
    && cp -r /tmp/kde-control-station/package /usr/share/plasma/plasmoids/com.github.prayag2.controlcentre \
    && rm -rf /tmp/kde-control-station \
    && python3 -c 'p="/usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/Task.qml"; s=open(p).read(); anim="\n            scale: task.highlighted ? 1.24 : 1.0\n            transformOrigin: Item.Bottom\n            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }\n"; s=s.replace("usesPlasmaTheme: false", "usesPlasmaTheme: false" + anim, 1) if "Behavior on scale" not in s else s; open(p,"w").write(s)' \
    && mkdir -p /etc/fonts \
    && printf '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n<fontconfig>\n  <match target="font">\n    <edit name="antialias" mode="assign"><bool>true</bool></edit>\n    <edit name="hinting" mode="assign"><bool>true</bool></edit>\n    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>\n    <edit name="rgba" mode="assign"><const>rgb</const></edit>\n    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>\n    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>\n  </match>\n</fontconfig>\n' > /etc/fonts/local.conf \
    && fc-cache -fv >/dev/null 2>&1 || true \
    && printf '[Desktop Entry]\nType=Application\nName=Automatic Package Installer\nComment=Automatically install .deb packages and update sources\nExec=/usr/local/bin/xrdp-deb-installer.sh %%F\nIcon=system-software-install\nTerminal=false\nNoDisplay=true\nMimeType=application/vnd.debian.binary-package;application/x-deb;application/x-debian-package;\n' > /usr/share/applications/xrdp-deb-installer.desktop \
    && update-desktop-database /usr/share/applications 2>/dev/null || true \
    && mkdir -p /etc/polkit-1/rules.d /var/lib/polkit-1/localauthority/50-local.d \
    && printf 'polkit.addRule(function(action, subject) {\n    if (subject.isInGroup("sudo")) {\n        return polkit.Result.YES;\n    }\n});\n' > /etc/polkit-1/rules.d/49-nopasswd-sudo.rules \
    && printf '[Allow all polkit actions for sudo group]\nIdentity=unix-group:sudo\nAction=*\nResultAny=yes\nResultInactive=yes\nResultActive=yes\n' > /var/lib/polkit-1/localauthority/50-local.d/49-nopasswd-sudo.pkla \
    && rm -f /etc/X11/Xsession.d/*appmenu* 2>/dev/null || true \
    && echo "UBUNTU_MENUPROXY=0" >> /etc/environment \
    && echo "CYCLES_ONEAPI_ALL_DEVICES=1" >> /etc/environment

# 4b. Install official Blender 4.2 LTS Foundation build (includes Intel oneAPI / SYCL Cycles GPU support)
RUN mkdir -p /opt/blender \
    && (curl -fsSL https://mirror.clarkson.edu/blender/release/Blender4.2/blender-4.2.3-linux-x64.tar.xz || curl -fsSL https://ftp.nluug.nl/graphics/blender/release/Blender4.2/blender-4.2.3-linux-x64.tar.xz) | tar -xJ -C /opt/blender --strip-components=1 \
    && ln -sf /opt/blender/blender /usr/local/bin/blender \
    && cp /opt/blender/blender.desktop /usr/share/applications/blender.desktop \
    && cp /opt/blender/blender.svg /usr/share/icons/hicolor/scalable/apps/blender.svg 2>/dev/null || true \
    && cp /opt/blender/blender.svg /usr/share/pixmaps/blender.svg 2>/dev/null || true \
    && update-desktop-database /usr/share/applications 2>/dev/null || true

COPY plasmoids/ /usr/share/plasma/plasmoids/
COPY xrdp-drives-sync.py /usr/local/bin/xrdp-drives-sync.py
COPY xrdp-deb-installer.sh /usr/local/bin/xrdp-deb-installer.sh
COPY xrdp-dock-helper.py /usr/local/bin/xrdp-dock-helper.py
COPY xrdp-timedate-daemon.py /usr/local/bin/xrdp-timedate-daemon.py
COPY org.freedesktop.timedate1.conf /etc/dbus-1/system.d/org.freedesktop.timedate1.conf
COPY vscode-launch /usr/local/bin/vscode-launch
COPY PicturesSheet.qml /usr/share/kpackage/kcms/kcm_users/contents/ui/PicturesSheet.qml
COPY UserDetailsPage.qml /usr/share/kpackage/kcms/kcm_users/contents/ui/UserDetailsPage.qml
RUN chmod +x /usr/local/bin/xrdp-drives-sync.py /usr/local/bin/xrdp-deb-installer.sh /usr/local/bin/xrdp-dock-helper.py /usr/local/bin/xrdp-timedate-daemon.py /usr/local/bin/vscode-launch \
    && ln -sf /usr/local/bin/vscode-launch /usr/local/bin/code \
    && ln -sf /usr/local/bin/vscode-launch /usr/share/code/code \
    && ln -sf /usr/local/bin/vscode-launch /usr/bin/code \
    && sed -i 's|^Icon=.*|Icon=/usr/share/icons/Mkos-Big-Sur/128x128/apps/vscode.svg|' /usr/share/applications/code.desktop 2>/dev/null || true \
    && cp /usr/share/applications/code.desktop /usr/share/applications/vscode.desktop 2>/dev/null || true \
    && update-desktop-database /usr/share/applications 2>/dev/null || true

COPY assets/wow-wallpaper.jpg /usr/share/backgrounds/xrdp-wow.jpg
COPY desktop-setup.sh /usr/local/bin/desktop-setup.sh
RUN chmod +x /usr/local/bin/desktop-setup.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Desktop environment and GPU/Hardware acceleration packages
#    Notes: libgl1-mesa-glx is not shipped in Ubuntu 24.04 (superseded by libgl1);
#    pulseaudio-module-xrdp is not packaged in 24.04 either and is built from
#    source in step 3 below; xrdp/xorgxrdp are built from source with x264 in
#    step 1b (Ubuntu's xrdp 0.9.24 has no H.264 support at all), so xserver-xorg-core
#    (pulled in by xorgxrdp's apt package) and libx264-164 (the encoder runtime)
#    are installed explicitly here.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xserver-xorg-core \
    libx264-164 \
    libfuse3-3 \
    fuse3 \
    libopus0 \
    xfce4 \
    xfce4-goodies \
    x11-xserver-utils \
    xfonts-base \
    dbus-x11 \
    sudo \
    curl \
    openssl \
    ca-certificates \
    mesa-va-drivers \
    mesa-vulkan-drivers \
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
    gnupg \
    git \
    htop \
    neofetch \
    arc-theme \
    papirus-icon-theme \
    fonts-firacode \
    gimp \
    inkscape \
    vlc \
    libreoffice \
    blender \
    glmark2-x11 \
    && rm -rf /var/lib/apt/lists/*

# 1b. Build xrdp 0.10.3 + xorgxrdp 0.10.3 from source with x264 H.264 encoding.
#     This is the fix for choppy video and laggy window drags: H.264 is a real
#     video codec with temporal compression, while RFX (all Ubuntu's xrdp 0.9.24
#     offers) re-encodes every frame as a still image. Configure flags mirror
#     Ubuntu's own xrdp build (debian/rules from xrdp_0.9.24-4) plus --enable-x264.
#     Installed to distro paths (/usr/sbin, /etc/xrdp) so the config steps below
#     and the entrypoint keep working unchanged. Build deps are purged in-layer.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config nasm \
        libx264-dev libfuse3-dev libjpeg-dev libopus-dev libpam0g-dev libssl-dev \
        libx11-dev libxfixes-dev libxrandr-dev \
        xserver-xorg-dev libgbm-dev libepoxy-dev libegl1-mesa-dev \
    && mkdir -p /tmp/xrdp-build && cd /tmp/xrdp-build \
    && curl -fsSL -o xrdp.tar.gz https://github.com/neutrinolabs/xrdp/releases/download/v0.10.3/xrdp-0.10.3.tar.gz \
    && tar xzf xrdp.tar.gz && cd xrdp-0.10.3 \
    && ./configure \
        --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
        --with-socketdir=/run/xrdp/sockdir \
        --enable-ipv6 --enable-jpeg --enable-fuse --enable-rfxcodec \
        --enable-opus --enable-painter --enable-vsock --enable-x264 \
    && make -j"$(nproc)" && make install \
    && cd /tmp/xrdp-build \
    && curl -fsSL -o xorgxrdp.tar.gz https://github.com/neutrinolabs/xorgxrdp/archive/refs/tags/v0.10.3.tar.gz \
    && tar xzf xorgxrdp.tar.gz && cd xorgxrdp-0.10.3 \
    && ./bootstrap && ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    && make -j"$(nproc)" && make install \
    && ldd /usr/sbin/xrdp | grep -q libx264 \
    && cd / && rm -rf /tmp/xrdp-build \
    && apt-get purge -y build-essential autoconf automake libtool pkg-config nasm \
        libx264-dev libfuse3-dev libjpeg-dev libopus-dev libpam0g-dev libssl-dev \
        libx11-dev libxfixes-dev libxrandr-dev \
        xserver-xorg-dev libgbm-dev libepoxy-dev libegl1-mesa-dev \
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
        > /etc/apt/sources.list.d/vscode.list && \
    apt-get update && apt-get install -y --no-install-recommends firefox code && \
    rm -rf /var/lib/apt/lists/*

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

# 7. Configure PulseAudio daemon and XRDP sinks
RUN sed -i 's/^; exit-idle-time = 20/exit-idle-time = -1/' /etc/pulse/daemon.conf && \
    sed -i 's/^; autospawn = yes/autospawn = yes/' /etc/pulse/client.conf && \
    echo "load-module module-xrdp-sink" >> /etc/pulse/default.pa && \
    echo "load-module module-xrdp-source" >> /etc/pulse/default.pa

# 8. Generate TLS Certificate
RUN openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem \
    -days 3650 -subj "/CN=rdp-container" && \
    chown root:root /etc/xrdp/key.pem /etc/xrdp/cert.pem && \
    chmod 600 /etc/xrdp/key.pem

# 9. Desktop wow factor: wallpaper + first-run beautification script
COPY assets/wow-wallpaper.jpg /usr/share/backgrounds/xrdp-wow.jpg
COPY desktop-setup.sh /usr/local/bin/desktop-setup.sh
RUN chmod +x /usr/local/bin/desktop-setup.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

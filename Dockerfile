FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Desktop environment, XRDP, and GPU/Hardware acceleration packages
#    Notes: libgl1-mesa-glx is not shipped in Ubuntu 24.04 (superseded by libgl1);
#    pulseaudio-module-xrdp is not packaged in 24.04 either and is built from
#    source in step 2 below.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xrdp \
    xorgxrdp \
    xfce4 \
    xfce4-goodies \
    x11-xserver-utils \
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
    && rm -rf /var/lib/apt/lists/*

# 2. Build pulseaudio-module-xrdp from source (neutrinolabs, v0.8).
#    Ubuntu 24.04 does not package the XRDP PulseAudio modules, and they must be
#    compiled against this release's exact PulseAudio sources (internal module API).
#    Build dependencies are purged in the same layer so the final image stays lean.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git autoconf libtool pkg-config meson ninja-build \
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
    && apt-get purge -y build-essential git autoconf libtool pkg-config meson ninja-build \
    && apt-get autoremove -y --purge \
    && rm -rf /var/lib/apt/lists/*

# 3. Install VirtualGL for headless 3D/OpenGL hardware offloading
RUN VGL_VER="3.1.1" \
    && curl -fsSL -o /tmp/virtualgl.deb \
       "https://github.com/VirtualGL/virtualgl/releases/download/${VGL_VER}/virtualgl_${VGL_VER}_amd64.deb" \
    && dpkg -i /tmp/virtualgl.deb \
    && rm -f /tmp/virtualgl.deb

# 4. Configure Xorg permissions for non-root execution inside container
RUN sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config 2>/dev/null || \
    echo "allowed_users=anybody" >> /etc/X11/Xwrapper.config && \
    echo "needs_root_rights=no" >> /etc/X11/Xwrapper.config

# 5. Configure XRDP for Credential Pass-Through, TLS, and Multi-Monitor
RUN sed -i 's/^autorun=.*/autorun=Xorg/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^#require_credentials=true/require_credentials=true/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^allow_multimon=false/allow_multimon=true/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^security_layer=negotiate/security_layer=tls/' /etc/xrdp/xrdp.ini

# 6. Configure PulseAudio daemon and XRDP sinks
RUN sed -i 's/^; exit-idle-time = 20/exit-idle-time = -1/' /etc/pulse/daemon.conf && \
    sed -i 's/^; autospawn = yes/autospawn = yes/' /etc/pulse/client.conf && \
    echo "load-module module-xrdp-sink" >> /etc/pulse/default.pa && \
    echo "load-module module-xrdp-source" >> /etc/pulse/default.pa

# 7. Generate TLS Certificate
RUN openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem \
    -days 3650 -subj "/CN=rdp-container" && \
    chown xrdp:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem && \
    chmod 600 /etc/xrdp/key.pem

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

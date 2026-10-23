FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Desktop environment, XRDP, and GPU/Hardware acceleration packages
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
    libgl1-mesa-glx \
    libvulkan1 \
    libxv1 \
    libglu1-mesa \
    libegl1 \
    libgl1 \
    pulseaudio \
    pulseaudio-utils \
    pulseaudio-module-xrdp \
    pavucontrol \
    alsa-utils \
    && rm -rf /var/lib/apt/lists/*

# 2. Install VirtualGL for headless 3D/OpenGL hardware offloading
RUN VGL_VER="3.1.1" \
    && curl -fsSL -o /tmp/virtualgl.deb \
       "https://github.com/VirtualGL/virtualgl/releases/download/${VGL_VER}/virtualgl_${VGL_VER}_amd64.deb" \
    && dpkg -i /tmp/virtualgl.deb \
    && rm -f /tmp/virtualgl.deb

# 3. Configure Xorg permissions for non-root execution inside container
RUN sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config 2>/dev/null || \
    echo "allowed_users=anybody" >> /etc/X11/Xwrapper.config && \
    echo "needs_root_rights=no" >> /etc/X11/Xwrapper.config

# 4. Configure XRDP for Credential Pass-Through, TLS, and Multi-Monitor
RUN sed -i 's/^autorun=.*/autorun=Xorg/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^#require_credentials=true/require_credentials=true/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^allow_multimon=false/allow_multimon=true/' /etc/xrdp/xrdp.ini && \
    sed -i 's/^security_layer=negotiate/security_layer=tls/' /etc/xrdp/xrdp.ini

# 5. Configure PulseAudio daemon and XRDP sinks
RUN sed -i 's/^; exit-idle-time = 20/exit-idle-time = -1/' /etc/pulse/daemon.conf && \
    sed -i 's/^; autospawn = yes/autospawn = yes/' /etc/pulse/client.conf && \
    echo "load-module module-xrdp-sink" >> /etc/pulse/default.pa && \
    echo "load-module module-xrdp-source" >> /etc/pulse/default.pa

# 6. Generate TLS Certificate
RUN openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem \
    -days 3650 -subj "/CN=rdp-container" && \
    chown xrdp:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem && \
    chmod 600 /etc/xrdp/key.pem

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

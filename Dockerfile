# syntax=docker/dockerfile:1.7

# OTBR (OpenThread Border Router) container image
#
# Single-stage build on Ubuntu LTS. OTBR's bootstrap/setup scripts install
# and configure system services (mDNS, dbus, etc.); a multi-stage split
# tends to drop required runtime state, so we stay single-stage on purpose.
FROM ubuntu:24.04

# ---- Build-time configuration --------------------------------------------
# Pin to a specific upstream ref. Upstream ot-br-posix does not cut regular
# semver tags on the main branch; "main" is used by default. Override with
# --build-arg OTBR_REF=<tag-or-sha> for reproducible builds.
ARG OTBR_REPO=https://github.com/openthread/ot-br-posix.git
ARG OTBR_REF=main

# Feature flags consumed by ot-br-posix's script/bootstrap + script/setup.
ARG REST_API=1
ARG WEB_GUI=1
ARG BORDER_ROUTING=1
ARG BACKBONE_ROUTER=1
ARG NAT64=1
ARG DNS64=0
ARG FIREWALL=1
ARG MDNS=openthread
ARG REFERENCE_DEVICE=0
ARG OTBR_OPTIONS="-DCPPHTTPLIB_REQUEST_URI_MAX_LENGTH=2048"

ENV DEBIAN_FRONTEND=noninteractive \
    PLATFORM=ubuntu \
    RELEASE=1 \
    REST_API=${REST_API} \
    WEB_GUI=${WEB_GUI} \
    BORDER_ROUTING=${BORDER_ROUTING} \
    BACKBONE_ROUTER=${BACKBONE_ROUTER} \
    NAT64=${NAT64} \
    DNS64=${DNS64} \
    FIREWALL=${FIREWALL} \
    MDNS=${MDNS} \
    REFERENCE_DEVICE=${REFERENCE_DEVICE} \
    OTBR_OPTIONS=${OTBR_OPTIONS}

# ---- Base packages -------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        sudo \
        iproute2 \
        iputils-ping \
        netbase \
        dbus \
        avahi-daemon \
        libavahi-client-dev \
        tini \
 && rm -rf /var/lib/apt/lists/*

# ---- Clone upstream OTBR at the pinned ref -------------------------------
WORKDIR /app
RUN git clone "${OTBR_REPO}" ot-br-posix \
 && git -C ot-br-posix fetch --depth 1 origin "${OTBR_REF}" \
 && git -C ot-br-posix checkout FETCH_HEAD \
 && git -C ot-br-posix submodule update --init --recursive --depth 1

# ---- Build & install OTBR ------------------------------------------------
WORKDIR /app/ot-br-posix
RUN ./script/bootstrap \
 && ./script/setup

# ---- Runtime environment defaults ----------------------------------------
ENV INFRA_IF_NAME=eth0 \
    BACKBONE_INTERFACE=eth0 \
    OT_INFRA_IF=eth0 \
    RADIO_URL="spinel+hdlc+uart:///dev/ttyACM0" \
    OT_RCP_DEVICE="spinel+hdlc+uart:///dev/ttyACM0" \
    TREL_URL="" \
    TUN_INTERFACE_NAME=wpan0 \
    OT_THREAD_IF=wpan0 \
    DEBUG_LEVEL=7 \
    OT_LOG_LEVEL=7 \
    HTTP_PORT=80 \
    HTTP_HOST=0.0.0.0 \
    REST_HOST=0.0.0.0

# Persistent state (Thread network dataset, settings, etc.)
VOLUME ["/data", "/var/lib/otbr"]

# ---- Entrypoint ----------------------------------------------------------
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# ---- Network surface -----------------------------------------------------
# 80   -> otbr-web (HTML/JS GUI)
# 8081 -> otbr-agent REST API
EXPOSE 80 8081

# ---- Healthcheck ---------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS --max-time 4 http://127.0.0.1:8081/node >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/app/entrypoint.sh"]

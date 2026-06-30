#!/usr/bin/env bash
#
# OTBR container entrypoint.
#
# Boots dbus, otbr-agent (with embedded REST API on :8081) and optionally
# otbr-web. Uses `wait -n` + signal trap so docker stop propagates cleanly.
#
set -euo pipefail

: "${INFRA_IF_NAME:=eth0}"
: "${RADIO_URL:=spinel+hdlc+uart:///dev/ttyACM0}"
: "${TUN_INTERFACE_NAME:=wpan0}"
: "${BACKBONE_INTERFACE:=${INFRA_IF_NAME}}"
: "${NAT64:=1}"
: "${BACKBONE_ROUTER:=1}"
: "${WEB_GUI:=1}"
: "${DEBUG_LEVEL:=7}"
: "${REST_PORT:=8081}"
: "${WEB_PORT:=80}"

log() { printf '[entrypoint] %s\n' "$*" >&2; }
die() { printf '[entrypoint][FATAL] %s\n' "$*" >&2; exit 1; }

# ---- Sanity: radio device ----------------------------------------------------
case "${RADIO_URL}" in
    *forkpty*|spinel+spi*|trel://*|"")
        log "RADIO_URL=${RADIO_URL} -- skipping device existence check"
        ;;
    *)
        radio_path="${RADIO_URL#*://}"
        radio_path="${radio_path%%\?*}"
        if [[ -z "${radio_path}" ]]; then
            die "Could not parse device path from RADIO_URL='${RADIO_URL}'"
        fi
        if [[ ! -e "${radio_path}" ]]; then
            die "Radio device '${radio_path}' (from RADIO_URL='${RADIO_URL}') not present in container. Pass it with '--device=${radio_path}' on docker run."
        fi
        if [[ ! -c "${radio_path}" && ! -b "${radio_path}" ]]; then
            log "WARN: '${radio_path}' exists but is not a char/block device -- continuing anyway"
        fi
        log "Radio device OK: ${radio_path}"
        ;;
esac

# ---- Sanity: TUN -------------------------------------------------------------
if [[ ! -c /dev/net/tun ]]; then
    die "/dev/net/tun missing. Pass '--device=/dev/net/tun' (and likely '--cap-add=NET_ADMIN') on docker run."
fi

# ---- Sanity: infra interface -------------------------------------------------
if ! ip link show "${INFRA_IF_NAME}" >/dev/null 2>&1; then
    log "WARN: infra interface '${INFRA_IF_NAME}' not visible in container."
fi

# ---- Start D-Bus -------------------------------------------------------------
mkdir -p /var/run/dbus
rm -f /var/run/dbus/pid /var/run/dbus/system_bus_socket
log "Starting dbus-daemon"
dbus-daemon --system --fork
for _ in 1 2 3 4 5; do
    [[ -S /var/run/dbus/system_bus_socket ]] && break
    sleep 0.2
done
[[ -S /var/run/dbus/system_bus_socket ]] || die "dbus-daemon failed to create system_bus_socket"

# ---- Shutdown handler --------------------------------------------------------
WEB_PID=""
AGENT_PID=""
shutdown() {
    log "Received signal -- shutting down"
    [[ -n "${WEB_PID}"   ]] && kill -TERM "${WEB_PID}"   2>/dev/null || true
    [[ -n "${AGENT_PID}" ]] && kill -TERM "${AGENT_PID}" 2>/dev/null || true
    wait 2>/dev/null || true
    exit 0
}
trap shutdown TERM INT

log "INFRA_IF_NAME=${INFRA_IF_NAME} BACKBONE_INTERFACE=${BACKBONE_INTERFACE}"
log "NAT64=${NAT64} BACKBONE_ROUTER=${BACKBONE_ROUTER} WEB_GUI=${WEB_GUI}"
log "RADIO_URL=${RADIO_URL} TUN=${TUN_INTERFACE_NAME}"

# ---- Launch otbr-agent (REST on :REST_PORT) ----------------------------------
AGENT_ARGS=(
    -I "${TUN_INTERFACE_NAME}"
    -B "${BACKBONE_INTERFACE}"
    --rest-listen-address "0.0.0.0"
    --rest-listen-port    "${REST_PORT}"
    --debug-level "${DEBUG_LEVEL}"
    "${RADIO_URL}"
)

log "Starting otbr-agent --rest ${AGENT_ARGS[*]}"
otbr-agent --rest "${AGENT_ARGS[@]}" &
AGENT_PID=$!

# ---- Optionally launch otbr-web ---------------------------------------------
if [[ "${WEB_GUI}" == "1" ]]; then
    sleep 1
    if command -v otbr-web >/dev/null 2>&1; then
        log "Starting otbr-web on :${WEB_PORT}"
        otbr-web -I "${TUN_INTERFACE_NAME}" -p "${WEB_PORT}" -a 0.0.0.0 &
        WEB_PID=$!
    else
        log "WEB_GUI=1 but otbr-web binary not found in image -- skipping"
    fi
fi

set +e
wait -n
exit_code=$?
set -e

log "A child process exited (code=${exit_code}). Tearing down."
shutdown

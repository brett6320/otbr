# OTBR with REST API

Containerized [OpenThread Border Router](https://openthread.io/guides/border-router) (OTBR) with the REST API enabled, published to GHCR for `linux/amd64` and `linux/arm64`. Wraps `openthread/ot-br-posix` so you can drop a Thread Border Router onto any Linux host with a Thread RCP attached over USB.

## What it is

- OTBR (`otbr-agent` + `otbr-web`) running in a single container.
- Built with `REST_API=1` so the JSON REST server inside `otbr-agent` is exposed on TCP **8081** alongside the web UI on port **80**.
- Multi-arch image published to `ghcr.io/OWNER/REPO`.

## Host requirements

- Linux host (kernel >= 5.10 recommended) with:
  - `tun` module (`/dev/net/tun`) for the `wpan0` interface.
  - `ip6tables` / `nf_tables` modules for firewall + BACKBONE_ROUTER features.
  - IPv6 enabled on the infra interface (e.g. `eth0`).
- A Thread **RCP** flashed onto a supported dongle (Nordic nRF52840, SiLabs EFR32, TI CC1352, etc.) at `/dev/ttyACM0` or `/dev/ttyUSB0`.
- Host networking (`network_mode: host`) — required for mDNS + IPv6 ND on the infra link.
- `NET_ADMIN` (and typically `SYS_ADMIN` when `BACKBONE_ROUTER=1`) caps.

## Quick start

```bash
ls /dev/ttyACM0
docker compose up -d
docker compose logs -f otbr
```

Web UI: `http://<host>/`  •  REST API: `http://<host>:8081/`

## REST API examples

> No auth, no TLS. Never expose 8081 to a LAN/WAN — put it behind a reverse proxy with TLS + auth, or restrict via firewall.

```bash
# Node info (NOTE: returns PSKc — treat as secret)
curl -s http://localhost:8081/node | jq

curl -s http://localhost:8081/node/state
curl -s http://localhost:8081/node/rloc16
curl -s http://localhost:8081/node/ext-address

# Active scan
curl -s http://localhost:8081/networks | jq

# Mesh diagnostics TLVs
curl -s http://localhost:8081/diagnostics | jq

# JSON:API v1 endpoints
curl -s -H 'Accept: application/vnd.api+json' \
  http://localhost:8081/api/devices | jq
```

Full schema: [`src/rest/openapi.yaml`](https://github.com/openthread/ot-br-posix/blob/main/src/rest/openapi.yaml).

## Pulling from GHCR

Built and pushed by `.github/workflows/build.yml` on every push to `main` and on semver tags.

```bash
docker pull ghcr.io/OWNER/REPO:latest
docker pull ghcr.io/OWNER/REPO:v1.2.3
docker pull ghcr.io/OWNER/REPO:sha-<short-sha>
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RADIO_URL` | `spinel+hdlc+uart:///dev/ttyACM0` | RCP device URL. |
| `TREL_URL` | (empty) | Thread Radio Encapsulation Link URL. |
| `TUN_INTERFACE_NAME` | `wpan0` | Thread TUN interface name. |
| `BACKBONE_INTERFACE` | `eth0` | Host infrastructure interface. |
| `INFRA_IF_NAME` | `eth0` | Alias for `BACKBONE_INTERFACE`. |
| `DEBUG_LEVEL` | `7` | syslog verbosity (0=emerg .. 7=debug). |
| `WEB_GUI` | `1` | Start `otbr-web` at runtime. |
| `REST_PORT` | `8081` | REST API port. |
| `WEB_PORT` | `80` | Web GUI port. |

Feature flags `REST_API`, `WEB_GUI`, `NAT64`, `DNS64`, `BACKBONE_ROUTER`, `BORDER_ROUTING`, `FIREWALL` are **compile-time** `--build-arg` values — rebuild to change them.

## License

OpenThread components are BSD-3-Clause (upstream). Glue here is MIT.

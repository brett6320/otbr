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

To run from the published GHCR image instead of building locally, copy [`docker-compose.sample.yaml`](./docker-compose.sample.yaml) to `docker-compose.yaml` and create a `.env` file using the sample below.

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

Built and pushed by `.github/workflows/build.yml` on every push to `main` and on `v*` semver tags. Image: `ghcr.io/brett6320/otbr`.

Current release: <!-- version:start -->**`0.1.0`**<!-- version:end -->

```bash
# latest stable (default branch HEAD)
docker pull ghcr.io/brett6320/otbr:latest

# pin to the current release
docker pull ghcr.io/brett6320/otbr:<!-- pull-version:start -->0.1.0<!-- pull-version:end -->

# also available: major / minor channels, and per-commit
docker pull ghcr.io/brett6320/otbr:<!-- pull-minor:start -->0.1<!-- pull-minor:end -->
docker pull ghcr.io/brett6320/otbr:<!-- pull-major:start -->0<!-- pull-major:end -->
docker pull ghcr.io/brett6320/otbr:sha-<short-sha>
```

These version markers are rewritten by `.github/workflows/release.yml` on every release so the README always reflects the published tag.

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

### Sample env vars

Drop this into a `.env` file next to your compose file, or pass through `docker run -e ...`. Tweak the interface and radio device for your host.

```dotenv
# Host-side infrastructure interface (must exist on the host with --network=host).
INFRA_IF_NAME=eth0
BACKBONE_INTERFACE=eth0

# Thread RCP device. Most USB dongles enumerate as ttyACM0; Silabs/FTDI parts
# as ttyUSB0. Use a stable /dev/serial/by-id/... path if multiple are attached.
RADIO_URL=spinel+hdlc+uart:///dev/ttyACM0

# Optional: Thread Radio Encapsulation Link (leave empty unless you know you need it).
TREL_URL=

# Thread TUN interface — exposed inside the container; rarely needs changing.
TUN_INTERFACE_NAME=wpan0

# Logging verbosity (0=emerg .. 7=debug).
DEBUG_LEVEL=7

# Service ports.
REST_PORT=8081
WEB_PORT=80
WEB_GUI=1
```

## Versioning

Single source of truth: the [`VERSION`](./VERSION) file (semver `MAJOR.MINOR.PATCH`).

To cut a release, trigger the **release** workflow from the Actions tab (or `gh workflow run release.yml -f bump=minor`). It defaults to a **minor** bump; pick `major` or `patch` to override. The workflow:

1. Bumps `VERSION` and commits to `main`.
2. Tags `vX.Y.Z` and pushes the tag.
3. Creates a GitHub Release with auto-generated notes.
4. The **build** workflow fires on the `v*` tag and publishes `ghcr.io/brett6320/otbr:{X.Y.Z, X.Y, X, latest}` (multi-arch).

Every image carries `org.opencontainers.image.version` and exposes `IMAGE_VERSION` / `IMAGE_REVISION` as env vars; `main` branch builds get an extra `X.Y.Z-dev.<sha>` tag.

## License

OpenThread components are BSD-3-Clause (upstream). Glue here is MIT.

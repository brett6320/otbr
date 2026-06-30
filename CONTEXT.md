# Project Context

Snapshot of decisions and state for this repo. Not auto-updated — refresh when scope changes.

## Purpose

Containerized [OpenThread Border Router (OTBR)](https://openthread.io/guides/border-router) with the REST API enabled. Wraps upstream `openthread/ot-br-posix`. Runs locally via `docker compose` or pulls from GHCR as `ghcr.io/brett6320/otbr`.

## Repo layout

| Path | Role |
|---|---|
| `Dockerfile` | Single-stage Ubuntu 24.04 build of ot-br-posix with `REST_API=1 WEB_GUI=1 BACKBONE_ROUTER=1 NAT64=1`. Pinned via `OTBR_REF` build-arg (default `main`). |
| `entrypoint.sh` | tini-wrapped boot: dbus → `otbr-agent --rest` on `0.0.0.0:8081` → optional `otbr-web`. Signal-clean via `wait -n` + TERM trap. Logs `IMAGE_VERSION` / `IMAGE_REVISION`. |
| `docker-compose.yml` | Local dev. `privileged: true`, `network_mode: host`, maps `/dev/ttyACM0` + `/dev/net/tun`, named volume for state. |
| `VERSION` | Single source of truth for semver. Starts at `0.1.0`. |
| `.github/workflows/build.yml` | Multi-arch (amd64+arm64) buildx → GHCR. Tags: `latest` on main, `vX.Y.Z` → `X.Y.Z`/`X.Y`/`X`, `sha-<short>`, plus `X.Y.Z-dev.<sha>` on main. OCI labels include version + revision. |
| `.github/workflows/release.yml` | `workflow_dispatch` with `bump` input (default `minor`, choices major/minor/patch). Bumps `VERSION`, commits, tags `vX.Y.Z`, pushes, creates GH Release. |
| `README.md` | User-facing docs: quick start, REST examples, env table, versioning. |
| `.dockerignore` | Excludes VCS / CI / docs / editor cruft from build context. |
| `.gitignore` | Excludes Claude artifacts, editor state, env files, logs. |

## Key decisions

- **Single-stage build.** OTBR's `script/bootstrap` + `script/setup` configure system services (dbus, avahi, sysctl). A multi-stage split drops runtime state — not worth the size win.
- **REST bind = 0.0.0.0.** Upstream default is loopback; we override via `--rest-listen-address` so the API is reachable through a port map (or host network). **No auth, no TLS** — must be fronted by a reverse proxy in any non-LAN deployment.
- **Host networking for compose.** Required for mDNS / IPv6 ND on the infra link. Bridge mode breaks Backbone Router. Documented tradeoff in compose file.
- **Privileged in compose.** Needed for runtime sysctl / ip6tables when `BACKBONE_ROUTER=1`. Tighter alt: `cap_add: [NET_ADMIN, SYS_ADMIN]` plus specific sysctls — left as a follow-up.
- **Versioning = file-based.** `VERSION` is the source; release workflow is the only writer. Default bump is **minor**; major/patch on request only.
- **Image self-reports.** `IMAGE_VERSION` / `IMAGE_REVISION` baked in as OCI labels + env. Entrypoint logs both on boot.

## Active branches / PRs

- `main` — initial commit (Dockerfile, entrypoint, compose, build.yml, README).
- `release-workflow` → **PR #1**: adds `VERSION`, `release.yml`, version stamping in build.yml + Dockerfile + entrypoint.

## Release flow

1. Merge changes to `main` (build.yml publishes `latest` + `0.1.0-dev.<sha>`).
2. `gh workflow run release.yml` — defaults to minor bump.
   - Override: `-f bump=major` or `-f bump=patch`.
3. Workflow tags `vX.Y.Z` → build.yml fires on tag → publishes `ghcr.io/brett6320/otbr:{X.Y.Z, X.Y, X, latest}` multi-arch.

## Open follow-ups

- Pin `OTBR_REF` to a specific upstream SHA once a known-good revision is identified (currently floats on `main`).
- Drop `privileged: true` in favor of explicit caps + sysctls.
- TLS / auth shim for the REST API (e.g. compose-side Caddy / Traefik example).
- CHANGELOG.md (currently relying on GH Release auto-notes).

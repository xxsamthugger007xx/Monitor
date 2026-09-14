# Monitoring Portal

A self-hosted observability stack for the Mii backend: **Prometheus** (metrics),
**Loki** (logs), and **Grafana** (dashboards/UI), running as native Linux
binaries with no containers.

## Why native binaries instead of Docker

This stack is built to run on a **Replit Reserved VM** (.5 CPU / 2GB RAM).
Replit does not reliably support Docker-in-Docker, so all three services run
as plain background processes launched from [`start.sh`](start.sh) — the
script downloads static Linux x86_64/arm64 binaries on first run and then
just execs them. There is no `docker-compose.yml` or Kubernetes manifest
anywhere in this repo, intentionally.

Replit deployments also expose exactly **one public port**. Only Grafana
needs to be reachable from the outside, so:

- Grafana listens on `0.0.0.0:3000` (public)
- Prometheus listens on `127.0.0.1:9090` (internal only)
- Loki listens on `127.0.0.1:3100` (internal only)

Grafana reaches Prometheus and Loki over localhost using the datasources
auto-provisioned from [`config/grafana-datasources.yml`](config/grafana-datasources.yml).

## Folder structure

```
Monitoring_portal/
├── start.sh                    # downloads binaries (first run only) + starts all 3 services
├── config/
│   ├── prometheus.yml          # scrape config
│   ├── loki-config.yml         # filesystem storage, no cloud backend
│   └── grafana-datasources.yml # provisions Prometheus + Loki as datasources
├── data/                        # gitignored — persistent storage (tsdb, loki chunks, grafana db)
├── bin/                          # gitignored — downloaded binaries
├── logs/                         # gitignored — stdout/stderr from each service
└── README.md
```

## Running locally

```bash
cd Monitoring_portal
export GF_ADMIN_PASSWORD="pick-a-real-password"   # optional locally, required in prod
./start.sh
```

First run downloads Prometheus, Loki, and Grafana into `bin/` (a few hundred
MB total) — subsequent runs skip the download and start immediately. The
script stays in the foreground (it `wait`s on all three background
processes), so run it with `&`, in `tmux`/`screen`, or as your process
manager's entrypoint if you don't want it to block your terminal.

Once running:

- Grafana UI: http://localhost:3000 (login `admin` / your `GF_ADMIN_PASSWORD`)
- Prometheus: http://127.0.0.1:9090 (localhost only, for debugging)
- Loki: http://127.0.0.1:3100 (localhost only, for debugging)

Stop with `Ctrl+C` — the script traps `SIGINT`/`SIGTERM` and shuts down all
three child processes.

## Deploying to Replit (Reserved VM)

1. Push this `Monitoring_portal/` folder to a new Repl (or a folder within
   an existing Repl).
2. In the Repl's Deployments tab, create a **Reserved VM** deployment
   (not Autoscale — this stack needs persistent local disk under `data/`
   and long-running background processes).
3. Set the deployment's **run command** to `./start.sh`.
4. Add `GF_ADMIN_PASSWORD` as a **Repl secret** (Deployments → Secrets) with
   a real password. If it's not set, `start.sh` falls back to a placeholder
   password and prints a loud warning — don't ship that to production.
5. Make sure the deployment exposes port `3000` as the public port (Replit
   Reserved VMs expose one public port; point it at Grafana).

Persistent storage (`data/prometheus`, `data/loki`, `data/grafana`) lives on
the Reserved VM's disk and survives restarts/redeploys as long as you don't
wipe the filesystem.

## Updating the scrape target

Right now [`config/prometheus.yml`](config/prometheus.yml) scrapes a
placeholder target:

```yaml
- job_name: "mii-backend"
  scheme: https
  metrics_path: /metrics
  static_configs:
    - targets: ["your-mii-app.replit.app"]
```

Once the real Mii backend has a metrics endpoint, replace
`your-mii-app.replit.app` with its actual domain and restart Prometheus
(or the whole stack via `start.sh`).

**Note:** exposing a `/metrics` endpoint on the Mii backend itself (e.g. via
`prom-client`/`client_python`/etc.) is a separate task and is not part of
this folder — this stack only scrapes an endpoint that already exists.

## Changing retention / storage

- Prometheus retention: `--storage.tsdb.retention.time` flag in
  [`start.sh`](start.sh), currently `30d`.
- Loki retention: `limits_config.retention_period` in
  [`config/loki-config.yml`](config/loki-config.yml), currently `720h` (30d).

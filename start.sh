#!/usr/bin/env bash
# Monitoring_portal/start.sh
#
# Downloads (once) and runs Prometheus + Loki + Grafana as native binaries,
# no Docker. Built for Replit Reserved VM (.5 CPU / 2GB RAM) where only one
# public port is exposed. Grafana (3000) is the only service bound to
# 0.0.0.0; Prometheus (9090) and Loki (3100) stay on 127.0.0.1 and are
# reached by Grafana internally as provisioned datasources.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

CONFIG_DIR="$ROOT_DIR/config"
DATA_DIR="$ROOT_DIR/data"
BIN_DIR="$ROOT_DIR/bin"

PROM_DIR="$BIN_DIR/prometheus"
LOKI_DIR="$BIN_DIR/loki"
GRAFANA_DIR="$BIN_DIR/grafana"

DOWNLOAD_TMP_ROOT="$ROOT_DIR/.download-tmp"

mkdir -p "$DATA_DIR/prometheus" "$DATA_DIR/loki/chunks" "$DATA_DIR/loki/rules" \
         "$DATA_DIR/loki/compactor" "$DATA_DIR/grafana" \
         "$DATA_DIR/grafana-provisioning/datasources" \
         "$BIN_DIR" "$ROOT_DIR/logs" "$DOWNLOAD_TMP_ROOT"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

log() { echo "[start.sh] $*"; }

# ---------------------------------------------------------------------------
# Prometheus
# ---------------------------------------------------------------------------
if [ ! -x "$PROM_DIR/prometheus" ]; then
  log "Prometheus binary not found, downloading latest stable release..."
  PROM_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/prometheus/prometheus/releases/latest)"
  PROM_VERSION="$(grep -m1 '"tag_name"' <<< "$PROM_RELEASE_JSON" | sed -E 's/.*"v([^"]+)".*/\1/')"
  PROM_TARBALL="prometheus-${PROM_VERSION}.linux-${GOARCH}.tar.gz"
  PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_TARBALL}"
  TMP_DIR="$(mktemp -d "$DOWNLOAD_TMP_ROOT/prometheus.XXXXXX")"
  log "Downloading $PROM_URL"
  curl -fsSL "$PROM_URL" -o "$TMP_DIR/prometheus.tar.gz"
  tar -xzf "$TMP_DIR/prometheus.tar.gz" -C "$TMP_DIR"
  mkdir -p "$PROM_DIR"
  cp "$TMP_DIR"/prometheus-*/prometheus "$PROM_DIR/"
  cp "$TMP_DIR"/prometheus-*/promtool "$PROM_DIR/" 2>/dev/null || true
  rm -rf "$TMP_DIR"
  log "Prometheus $PROM_VERSION installed."
else
  log "Prometheus binary already present, skipping download."
fi

# ---------------------------------------------------------------------------
# Loki
# ---------------------------------------------------------------------------
if [ ! -x "$LOKI_DIR/loki" ]; then
  log "Loki binary not found, downloading latest stable release..."
  LOKI_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/grafana/loki/releases/latest)"
  LOKI_VERSION="$(grep -m1 '"tag_name"' <<< "$LOKI_RELEASE_JSON" | sed -E 's/.*"v?([^"]+)".*/\1/')"
  LOKI_ZIP="loki-linux-${GOARCH}.zip"
  LOKI_URL="https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/${LOKI_ZIP}"
  TMP_DIR="$(mktemp -d "$DOWNLOAD_TMP_ROOT/loki.XXXXXX")"
  log "Downloading $LOKI_URL"
  curl -fsSL "$LOKI_URL" -o "$TMP_DIR/loki.zip"
  mkdir -p "$LOKI_DIR"
  unzip -oq "$TMP_DIR/loki.zip" -d "$TMP_DIR"
  cp "$TMP_DIR/loki-linux-${GOARCH}" "$LOKI_DIR/loki"
  chmod +x "$LOKI_DIR/loki"
  rm -rf "$TMP_DIR"
  log "Loki $LOKI_VERSION installed."
else
  log "Loki binary already present, skipping download."
fi

# ---------------------------------------------------------------------------
# Grafana
# ---------------------------------------------------------------------------
if [ ! -x "$GRAFANA_DIR/bin/grafana" ]; then
  log "Grafana binary not found, downloading latest stable release..."
  GRAFANA_RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/grafana/grafana/releases/latest)"
  GRAFANA_VERSION="$(grep -m1 '"tag_name"' <<< "$GRAFANA_RELEASE_JSON" | sed -E 's/.*"v?([^"]+)".*/\1/')"
  GRAFANA_TARBALL="grafana-${GRAFANA_VERSION}.linux-${GOARCH}.tar.gz"
  GRAFANA_URL="https://dl.grafana.com/oss/release/${GRAFANA_TARBALL}"
  TMP_DIR="$(mktemp -d "$DOWNLOAD_TMP_ROOT/grafana.XXXXXX")"
  log "Downloading $GRAFANA_URL"
  curl -fsSL "$GRAFANA_URL" -o "$TMP_DIR/grafana.tar.gz"
  tar -xzf "$TMP_DIR/grafana.tar.gz" -C "$TMP_DIR"
  mkdir -p "$GRAFANA_DIR"
  cp -r "$TMP_DIR"/grafana-v"${GRAFANA_VERSION}"*/* "$GRAFANA_DIR/" 2>/dev/null || cp -r "$TMP_DIR"/grafana-*/* "$GRAFANA_DIR/"
  rm -rf "$TMP_DIR"
  log "Grafana $GRAFANA_VERSION installed."
else
  log "Grafana binary already present, skipping download."
fi

rmdir "$DOWNLOAD_TMP_ROOT" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Wire up Grafana datasource provisioning (Grafana expects a directory tree;
# we keep the single source-of-truth file in config/ and drop it into the
# expected location on every start).
# ---------------------------------------------------------------------------
cp "$CONFIG_DIR/grafana-datasources.yml" "$DATA_DIR/grafana-provisioning/datasources/grafana-datasources.yml"

# ---------------------------------------------------------------------------
# Admin password
# ---------------------------------------------------------------------------
if [ -z "${GF_ADMIN_PASSWORD:-}" ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "WARNING: GF_ADMIN_PASSWORD is not set. Using placeholder 'changeme-now'."
  echo "Set GF_ADMIN_PASSWORD as a Repl secret before deploying to production."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  GF_ADMIN_PASSWORD="changeme-now"
fi

# ---------------------------------------------------------------------------
# Start services (background), logs to ./logs
# ---------------------------------------------------------------------------
log "Starting Prometheus on 127.0.0.1:9090 ..."
"$PROM_DIR/prometheus" \
  --config.file="$CONFIG_DIR/prometheus.yml" \
  --storage.tsdb.path="$DATA_DIR/prometheus" \
  --storage.tsdb.retention.time=30d \
  --web.listen-address=127.0.0.1:9090 \
  > "$ROOT_DIR/logs/prometheus.log" 2>&1 &
PROM_PID=$!

log "Starting Loki on 127.0.0.1:3100 ..."
"$LOKI_DIR/loki" \
  -config.file="$CONFIG_DIR/loki-config.yml" \
  > "$ROOT_DIR/logs/loki.log" 2>&1 &
LOKI_PID=$!

log "Starting Grafana on 0.0.0.0:3000 ..."
GF_PATHS_DATA="$DATA_DIR/grafana/data" \
GF_PATHS_LOGS="$DATA_DIR/grafana/logs" \
GF_PATHS_PLUGINS="$DATA_DIR/grafana/plugins" \
GF_PATHS_PROVISIONING="$DATA_DIR/grafana-provisioning" \
GF_SERVER_HTTP_ADDR="0.0.0.0" \
GF_SERVER_HTTP_PORT="3000" \
GF_SECURITY_ADMIN_PASSWORD="$GF_ADMIN_PASSWORD" \
  "$GRAFANA_DIR/bin/grafana" server \
  --homepath="$GRAFANA_DIR" \
  > "$ROOT_DIR/logs/grafana.log" 2>&1 &
GRAFANA_PID=$!

log "Prometheus PID $PROM_PID | Loki PID $LOKI_PID | Grafana PID $GRAFANA_PID"

# Forward termination signals to children so the deployment shuts down cleanly.
trap 'log "Stopping..."; kill "$PROM_PID" "$LOKI_PID" "$GRAFANA_PID" 2>/dev/null' TERM INT

# Keep the script (and therefore the Reserved VM process) alive as long as
# any of the three services are running.
wait -n "$PROM_PID" "$LOKI_PID" "$GRAFANA_PID"
log "One of the services exited, shutting down the rest..."
kill "$PROM_PID" "$LOKI_PID" "$GRAFANA_PID" 2>/dev/null || true
wait

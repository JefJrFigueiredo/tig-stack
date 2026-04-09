# TIG Stack - Development Guide

## Stack

Telegraf → InfluxDB → Grafana — system metrics collection, storage, and visualization with automatic downsampling.

## Downsampling Tiers

| Frequency | Retention | Samples at boundary |
|-----------|-----------|---------------------|
| 5s        | 3h        | 2160                |
| 1m        | 36h       | 2160                |
| 5m        | 7d        | 2016                |
| 1h        | 90d       | 2160                |
| 4h        | 1y        | 2190                |
| 1d        | 6y        | 2190                |
| 1w        | forever   | —                   |

## Data Flow

```
Telegraf (5s) → <bucket>      (3h retention)    fields: field_name
                     ↓ task_1min.flux  (every 1m)
                <bucket>_1min  (36h)             fields: field_name_mean/min/max
                     ↓ task_5min.flux  (every 5m)
                <bucket>_5min  (7d)              fields: field_name_mean/min/max
                     ↓ task_1h.flux    (every 1h)
                <bucket>_1h    (90d)             fields: field_name_mean/min/max
                     ↓ task_4h.flux    (every 4h)
                <bucket>_4h    (365d)            fields: field_name_mean/min/max
                     ↓ task_1d.flux    (every 1d)
                <bucket>_1d    (2190d)           fields: field_name_mean/min/max
                     ↓ task_1w.flux    (every 1w)
                <bucket>_1w    (forever)         fields: field_name_mean/min/max
```

`<bucket>` = `DOCKER_INFLUXDB_INIT_BUCKET` from `.env`

The raw bucket stores bare field names (e.g., `usage_idle`). Downsampled buckets store three variants per field: `usage_idle_mean`, `usage_idle_min`, `usage_idle_max`. The `_min` and `_max` variants are used in Grafana to render a shaded min/max band around the mean line.

## Common Tasks

### Add a downsampling task
1. Create `influxdb/task_NAME.flux` using `INIT_BUCKET_NAME` placeholders
2. If reading from the raw bucket (first tier): follow the `getBase()` + `union()` pattern from `task_1min.flux` — no `import "strings"` needed, append `_mean`/`_min`/`_max` with `map()`
3. If reading from an already-downsampled bucket: use `import "strings"` + `strings.hasSuffix` to filter by suffix and apply the correct aggregation function per branch (`fn: min` for `_min` fields, etc.)
4. Add bucket creation + task creation in `influxdb/entrypoint.sh`
5. `docker compose down && docker compose up -d`

### Change downsampling intervals
1. Edit `every:` in `task_*.flux`
2. Update retention in `influxdb/entrypoint.sh` (applies to new setups only — existing buckets need `influx bucket update` or a full reset)
3. `docker compose down && docker compose up -d`

### Add Telegraf metrics
1. Add input plugin to `telegraf/telegraf.conf` (for all users), or to a `.conf` file in `telegraf/telegraf.d/` (for local/optional plugins)
2. `docker compose down && docker compose up -d`

### Enable GPU monitoring

See `docs/gpu-monitoring.md` for vendor-specific setup (NVIDIA, AMD, WSL2).

GPU monitoring uses the local override convention (see below) — nothing is committed to the repo. NVIDIA string field exclusions are already in `task_1min.flux` (no-op when GPU monitoring is disabled).

### Drop-in overrides

Optional configuration can be added via drop-in directories without modifying base files. All paths below are gitignored by default:

| Directory | Purpose | Convention |
|-----------|---------|------------|
| `docker-compose.override.yml` | Compose overrides (extra volumes, image swaps, device reservations) | Auto-merged by `docker compose` |
| `telegraf/telegraf.d/*.conf` | Drop-in Telegraf input plugins | Auto-loaded by Telegraf alongside `telegraf.conf` |
| `grafana/dashboards.d/*.json` | Drop-in Grafana panels | Merged into `system-metrics.json` at startup by `grafana/entrypoint.sh` |
| `influxdb/influxdb.d/*.flux` | Drop-in InfluxDB tasks | Upserted at startup by `influxdb/entrypoint.sh` |

Drop-in files support `INIT_BUCKET_NAME` and `INIT_ORG_NAME` placeholders (substituted by entrypoints). The `docker-compose.override.yml` must mount the drop-in directories into the containers — see `docs/gpu-monitoring.md` for a full example.

**Drop-in directories are for local-only config** (e.g., GPU monitoring). Shared configuration that should be committed belongs in the standard locations: `telegraf/telegraf.conf`, `influxdb/task_*.flux`, `grafana/provisioning/dashboards/system-metrics.json`.

### Verify tasks
```bash
docker exec tig-stack-influxdb-1 influx task list -t $TOKEN
docker exec tig-stack-influxdb-1 influx task run list --task-id=$TASK_ID -t $TOKEN
docker exec tig-stack-influxdb-1 influx task log list --task-id=$TASK_ID -t $TOKEN
```

## Critical Constraints

- **Template placeholders**: `.flux`, `system-metrics.json`, `dashboards.d/*.json`, and `influxdb.d/*.flux` use `INIT_BUCKET_NAME` and `INIT_ORG_NAME` — entrypoint scripts use `sed` to substitute at runtime; `INIT_BUCKET_NAME` in any placeholder (e.g. `INIT_BUCKET_NAME_1min`) is replaced by the bucket name, leaving the suffix intact
- **Grafana datasource**: edit `influxdb.yml.template`, not the generated `.yml`
- **Dashboard changes**: increment the `version` field for Grafana to detect updates
- **Bucket selection logic**: use `timeAgoNs = uint(v: now()) - uint(v: v.timeRangeStart)` (age of data, not query duration) — ≤3h → raw, ≤36h → _1min, ≤7d → _5min, ≤90d → _1h, ≤365d → _4h, ≤2190d → _1d, else → _1w
- **Downsampled field naming**: downsampled buckets use `field_name_mean/min/max` suffixes — Grafana queries use `isRaw` flag to select the correct field name per bucket tier, and `set(key: "_field", ...)` to normalize series names for overrides
- **String fields**: exclude from aggregation (e.g., `uptime_format`) — use `filter(fn: (r) => r["_field"] != "field_name")` in the first-tier task; no need to repeat in subsequent tiers since the field never enters the downsampled bucket
- **Cumulative counter fields**: measurements like `net` store monotonically increasing totals (e.g., `bytes_sent`, `bytes_recv`) — exclude them from the normal `getBase()` path in `task_1min.flux`, apply `derivative(unit: 1s, nonNegative: true)` to convert to rates (bytes/sec), query `-2m` for context, and use `tail(n: 1)` to avoid writing the previous window. Subsequent tiers handle the resulting `_mean/min/max` fields normally.
- **Grafana queries for cumulative-derived fields**: use the `filter(fn: (r) => isRaw)` trick to split into two branches (`rawPath` with derivative + `dsPath` without), then `union()` them — the false-filtered branch returns an empty stream so only the correct path contributes data
- **Entrypoint idempotency**: only `influx setup` is guarded by `/api/v2/setup`; bucket creation (idempotent via `|| echo "already exists"`) and task upsert (create-or-update by name) run on every start, so changes to `.flux` files or new buckets take effect with a simple restart
- **All `influx` CLI commands** require `-t $TOKEN`

## Data Persistence

Data survives `docker compose down && up` via named volumes.

**Safe restart** (preserves data, applies config changes):
```bash
docker compose down && docker compose up -d
```

This applies changes to `task_*.flux`, new buckets in `entrypoint.sh`, `telegraf.conf`, `telegraf.d/` drop-ins, `influxdb.d/` drop-ins, `dashboards.d/` drop-ins, and Grafana datasources — all without losing data. This is the **standard workflow** for most changes.

**Full reset** (deletes all data, re-runs zero-config setup from scratch):
```bash
docker compose down -v && docker compose up -d
```

Only needed when you want a clean slate (e.g., schema changes to existing buckets, changing retention periods on existing buckets, or corruption).

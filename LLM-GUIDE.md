# TIG Stack - LLM Development Guide

## Architecture Overview

**Stack**: Telegraf → InfluxDB → Grafana  
**Purpose**: System metrics collection, storage, and visualization with automatic downsampling

## Project Structure

```
tig-stack/
├── docker-compose.yml          # Main orchestration
├── .env                        # Environment variables (credentials, ports)
├── influxdb/
│   ├── entrypoint.sh          # Auto-setup: buckets + tasks (substitutes env vars)
│   ├── task_20s.flux          # Downsample template: uses "INIT_BUCKET_NAME" placeholders
│   └── task_1min.flux         # Downsample template: uses "INIT_BUCKET_NAME" placeholders
├── telegraf/
│   └── telegraf.conf          # Metrics collection config (5s interval)
└── grafana/
    ├── entrypoint.sh          # Substitutes env vars into datasource + dashboard
    └── provisioning/
        ├── datasources/
        │   └── influxdb.yml.template   # Datasource template (uses ${VARS})
        └── dashboards/
            ├── dashboard-provider.yml  # Dashboard provider config
            └── system-metrics.json     # Dashboard template (uses "INIT_BUCKET_NAME" placeholders)
```

## Data Flow

```
Telegraf (5s) → changeme bucket (1h retention)
                      ↓ task_20s.flux (runs every 20s)
                 changeme_20s (1d retention)
                      ↓ task_1min.flux (runs every 1min)
                 changeme_1min (7d retention)
```

## Key Components

### InfluxDB
- **Volume**: `influxdb-storage:/var/lib/influxdb2` (named volume for persistence)
- **Data path**: Set via `INFLUXD_BOLT_PATH=/var/lib/influxdb2/influxd.bolt` (derives engine, sqlite paths)
- **Entrypoint**: `/influxdb/entrypoint.sh` (checks if initialized via `/api/v2/setup` API)
- **Auto-creates**: Buckets + downsampling tasks (only on first run)
- **Restart policy**: `unless-stopped`

### Grafana
- **Volume**: `./grafana:/grafana:ro`
- **Entrypoint**: `/grafana/entrypoint.sh` (substitutes `.env` vars into datasource + dashboard)
- **Templates**: 
  - `influxdb.yml.template`: Uses `${VARS}` for datasource config
  - `system-metrics.json`: Uses "INIT_BUCKET_NAME" placeholders for bucket names
- **Substitution**: `sed` replaces placeholders with actual values from `.env`
- **Datasource**: Single InfluxDB datasource (auto-selects bucket in queries)
- **Dashboard**: Queries automatically select optimal bucket based on time range

### InfluxDB Entrypoint Workflow
1. Start `influxd` in background
2. Wait for ready (30 retries, 2s interval)
3. **Check if initialized**: Query `/api/v2/setup` API (`{"allowed": false}` = skip setup)
4. If not initialized: Run `influx setup` (org, bucket, user, token)
5. Create downsampling buckets (`_20s`, `_1min`)
6. Substitute bucket/org names in `.flux` files using `sed`
7. Create tasks from substituted flux files
8. Bring `influxd` to foreground

### Flux Tasks (`.flux` files)
- **Location**: `/influxdb/*.flux`
- **Template placeholders**: Use "INIT_BUCKET_NAME", "INIT_BUCKET_NAME_20s", "INIT_BUCKET_NAME_1min", "INIT_ORG_NAME"
- **Substitution**: Entrypoint uses `sed` to replace with actual bucket names from `.env`
- **Must exclude**: `uptime_format` field (string type, breaks aggregation)
- **Structure**: `option task = {...}` + query + `to()` function

## Environment Variables (`.env`)

Required (used by InfluxDB, Telegraf, and Grafana):
```bash
DOCKER_INFLUXDB_INIT_MODE=setup
DOCKER_INFLUXDB_INIT_ORG=<org_name>
DOCKER_INFLUXDB_INIT_BUCKET=<bucket_name>
DOCKER_INFLUXDB_INIT_RETENTION=<e.g., 96h>
DOCKER_INFLUXDB_INIT_USERNAME=<username>
DOCKER_INFLUXDB_INIT_PASSWORD=<password>
DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=<token>
DOCKER_INFLUXDB_INIT_PORT=8086
DOCKER_INFLUXDB_INIT_HOST=influxdb
GRAFANA_PORT=3000
TELEGRAF_CFG_PATH=./telegraf/telegraf.conf
```

## Common Tasks

### Add New Downsampling Task
1. Create `influxdb/task_NAME.flux`
2. Add bucket creation in `entrypoint.sh` (lines 44-59)
3. Add task creation in `entrypoint.sh` (lines 61-78)
4. Restart: `docker compose restart influxdb`

### Change Downsampling Intervals
1. Edit `task_*.flux` → change `every:` value
2. Edit `entrypoint.sh` → update retention periods
3. Restart: `docker compose restart influxdb`

### Add New Metrics (Telegraf)
1. Edit `telegraf/telegraf.conf`
2. Add input plugin (e.g., `[[inputs.cpu]]`)
3. Restart: `docker compose restart telegraf`

### Verify Tasks
```bash
# List tasks
docker exec tig-stack-influxdb-1 influx task list -t $TOKEN

# Check task runs
docker exec tig-stack-influxdb-1 influx task run list --task-id=$TASK_ID -t $TOKEN

# View logs
docker exec tig-stack-influxdb-1 influx task log list --task-id=$TASK_ID -t $TOKEN
```

## Critical Constraints

1. **String fields**: Exclude from aggregation (use `filter(fn: (r) => r["_field"] != "field_name")`)
2. **Token required**: All `influx` CLI commands need `-t $TOKEN`
3. **Bucket naming**: Use `${DOCKER_INFLUXDB_INIT_BUCKET}_suffix` pattern
4. **Template files**: Use "INIT_BUCKET_NAME", "INIT_ORG_NAME" placeholders in `.flux` and `.json` files
5. **Entrypoint substitution**: Both entrypoints use `sed` to replace placeholders with `.env` values
6. **Entrypoint idempotency**: Use `|| echo "already exists"` for creates
7. **File permissions**: `entrypoint.sh` must be executable (`chmod +x`)
8. **Grafana datasource**: Edit `.template` file, not generated `.yml`
9. **Volume mounts**: All service dirs mounted as `./service:/service:ro`
10. **Dashboard queries**: Use conditional bucket selection based on time range
11. **Dashboard versions**: Increment version number for Grafana to detect changes
12. **Bucket selection logic**: Use `timeAgoNs = uint(v: now()) - uint(v: v.timeRangeStart)` to calculate data age, not query duration
13. **Age-based selection**: ≤1h → raw, ≤24h → 20s, >24h → 1min (based on how old data is from now)

## Data Persistence

Data survives `docker compose down && up` via named volumes and `INFLUXD_BOLT_PATH`. The entrypoint checks `/api/v2/setup` API to avoid re-initialization.

**Safe restart** (preserves data):
```bash
docker compose down && docker compose up -d
docker compose restart influxdb  # or grafana, telegraf
```

**⚠️ DANGER: Full reset** (deletes all data):
```bash
docker compose down -v  # Note the -v flag
docker compose up -d
```

## Ports

- InfluxDB: `${DOCKER_INFLUXDB_INIT_PORT}` (default: 8086)
- Grafana: `${GRAFANA_PORT}` (default: 3000)

## Notes for LLMs

- All initialization is automatic via `entrypoint.sh`
- Volume mount pattern: `./local/path:/container/path:ro`
- Flux tasks run in InfluxDB's scheduler (not cron)
- Task failures: Check logs for string field errors

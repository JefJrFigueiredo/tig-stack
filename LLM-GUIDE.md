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
│   ├── entrypoint.sh          # Auto-setup: buckets + tasks
│   ├── task_20s.flux          # Downsample: 10s → 20s (every 20s)
│   └── task_1min.flux         # Downsample: 20s → 1min (every 1min)
├── telegraf/
│   └── telegraf.conf          # Metrics collection config (10s interval)
└── grafana/
    ├── entrypoint.sh          # Substitutes env vars into datasource
    └── provisioning/
        └── datasources/
            └── influxdb.yml.template   # Datasource template (uses ${VARS})
```

## Data Flow

```
Telegraf (10s) → changeme bucket (4d retention)
                      ↓ task_20s.flux (runs every 20s)
                 changeme_20s (1d retention)
                      ↓ task_1min.flux (runs every 1min)
                 changeme_1min (7d retention)
```

## Key Components

### InfluxDB
- **Volume**: `./influxdb:/influxdb:ro`
- **Entrypoint**: `/influxdb/entrypoint.sh` (runs on first start)
- **Auto-creates**: Buckets + downsampling tasks

### Grafana
- **Volume**: `./grafana:/grafana:ro`
- **Entrypoint**: `/grafana/entrypoint.sh` (substitutes `.env` vars into datasource)
- **Template**: Uses `sed` to replace `${VARS}` in `influxdb.yml.template`

### InfluxDB Entrypoint Workflow
1. Start `influxd` in background
2. Wait for ready (30 retries, 2s interval)
3. Run `influx setup` (org, bucket, user, token)
4. Create downsampling buckets (`_20s`, `_1min`)
5. Create tasks from `.flux` files
6. Bring `influxd` to foreground

### Flux Tasks (`.flux` files)
- **Location**: `/influxdb/*.flux`
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
4. **Entrypoint idempotency**: Use `|| echo "already exists"` for creates
5. **File permissions**: `entrypoint.sh` must be executable (`chmod +x`)
6. **Grafana datasource**: Edit `.template` file, not generated `.yml`
7. **Volume mounts**: All service dirs mounted as `./service:/service:ro`

## Reset & Fresh Start

```bash
# Full reset (deletes all data)
docker compose down
docker volume rm tig-stack_influxdb-storage tig-stack_grafana-storage
docker compose up -d

# InfluxDB only
docker compose stop influxdb
docker compose rm -f influxdb
docker volume rm tig-stack_influxdb-storage
docker compose up -d influxdb
```

## Ports

- InfluxDB: `${DOCKER_INFLUXDB_INIT_PORT}` (default: 8086)
- Grafana: `${GRAFANA_PORT}` (default: 3000)

## Notes for LLMs

- All initialization is automatic via `entrypoint.sh`
- Volume mount pattern: `./local/path:/container/path:ro`
- Flux tasks run in InfluxDB's scheduler (not cron)
- Task failures: Check logs for string field errors

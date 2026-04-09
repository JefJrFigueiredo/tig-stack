#!/bin/bash

# Protects script from continuing with an error
set -eu -o pipefail

# Ensures environment variables are set
export DOCKER_INFLUXDB_INIT_MODE=$DOCKER_INFLUXDB_INIT_MODE
export DOCKER_INFLUXDB_INIT_USERNAME=$DOCKER_INFLUXDB_INIT_USERNAME
export DOCKER_INFLUXDB_INIT_PASSWORD=$DOCKER_INFLUXDB_INIT_PASSWORD
export DOCKER_INFLUXDB_INIT_ORG=$DOCKER_INFLUXDB_INIT_ORG
export DOCKER_INFLUXDB_INIT_BUCKET=$DOCKER_INFLUXDB_INIT_BUCKET
export DOCKER_INFLUXDB_INIT_RETENTION=$DOCKER_INFLUXDB_INIT_RETENTION
export DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=$DOCKER_INFLUXDB_INIT_ADMIN_TOKEN
export DOCKER_INFLUXDB_INIT_PORT=$DOCKER_INFLUXDB_INIT_PORT
export DOCKER_INFLUXDB_INIT_HOST=$DOCKER_INFLUXDB_INIT_HOST

INFLUX_HOST="http://localhost:${DOCKER_INFLUXDB_INIT_PORT}"
INFLUX_COMMON="-t ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN} --host ${INFLUX_HOST}"

# Start InfluxDB in the background
influxd &
INFLUX_PID=$!

# Wait for InfluxDB to be ready
echo "Waiting for InfluxDB to start..."
for i in {1..30}; do
    if influx ping --host ${INFLUX_HOST} &>/dev/null; then
        echo "InfluxDB is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# --- One-time setup (user, org, token) ---
SETUP_ALLOWED=$(curl -s ${INFLUX_HOST}/api/v2/setup | grep -o '"allowed":[^,}]*' | cut -d':' -f2 | tr -d ' ')

if [ "$SETUP_ALLOWED" = "false" ]; then
    echo "InfluxDB already initialized. Skipping initial setup..."
else
    echo "Setting up InfluxDB..."
    influx setup --skip-verify \
        --bucket    ${DOCKER_INFLUXDB_INIT_BUCKET} \
        --retention ${DOCKER_INFLUXDB_INIT_RETENTION} \
        --token     ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN} \
        --org       ${DOCKER_INFLUXDB_INIT_ORG} \
        --username  ${DOCKER_INFLUXDB_INIT_USERNAME} \
        --password  ${DOCKER_INFLUXDB_INIT_PASSWORD} \
        --host      ${INFLUX_HOST} \
        --force
fi

# --- Buckets (idempotent — runs every start) ---
echo "Ensuring downsampling buckets exist..."
declare -A BUCKET_RETENTIONS=(
    ["1min"]="36h"
    ["5min"]="7d"
    ["1h"]="90d"
    ["4h"]="365d"
    ["1d"]="2190d"
    ["1w"]="0"
)

for suffix in 1min 5min 1h 4h 1d 1w; do
    influx bucket create \
        --name "${DOCKER_INFLUXDB_INIT_BUCKET}_${suffix}" \
        --org ${DOCKER_INFLUXDB_INIT_ORG} \
        --retention ${BUCKET_RETENTIONS[$suffix]} \
        ${INFLUX_COMMON} || echo "Bucket _${suffix} already exists"
done

# --- Tasks (upsert — creates or updates on every start) ---
echo "Upserting downsampling tasks..."
for task_file in task_1min task_5min task_1h task_4h task_1d task_1w; do
    if [ ! -f /influxdb/${task_file}.flux ]; then
        continue
    fi

    # Render placeholders
    sed -e "s/INIT_ORG_NAME/${DOCKER_INFLUXDB_INIT_ORG}/g" \
        -e "s/INIT_BUCKET_NAME/${DOCKER_INFLUXDB_INIT_BUCKET}/g" \
        /influxdb/${task_file}.flux > /tmp/${task_file}.flux

    # Extract task name from the flux file (e.g. name: "downsample-all-to-1min")
    TASK_NAME=$(sed -n 's/.*name:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/${task_file}.flux | head -1)

    # Look up existing task ID by name
    TASK_ID=$(influx task list ${INFLUX_COMMON} --org ${DOCKER_INFLUXDB_INIT_ORG} \
        | grep "${TASK_NAME}" | awk '{print $1}') || true

    if [ -n "$TASK_ID" ]; then
        echo "Updating task ${TASK_NAME} (${TASK_ID})..."
        influx task update --id ${TASK_ID} --file /tmp/${task_file}.flux ${INFLUX_COMMON} \
            || echo "Failed to update task ${TASK_NAME}"
    else
        echo "Creating task ${TASK_NAME}..."
        influx task create --org ${DOCKER_INFLUXDB_INIT_ORG} --file /tmp/${task_file}.flux ${INFLUX_COMMON} \
            || echo "Task ${TASK_NAME} already exists"
    fi
done

# --- Drop-in tasks from influxdb.d/ (same upsert logic) ---
if [ -d /influxdb.d ] && ls /influxdb.d/*.flux >/dev/null 2>&1; then
    echo "Processing drop-in tasks from influxdb.d/..."
    for task_file in /influxdb.d/*.flux; do
        base=$(basename "$task_file" .flux)

        # Render placeholders
        sed -e "s/INIT_ORG_NAME/${DOCKER_INFLUXDB_INIT_ORG}/g" \
            -e "s/INIT_BUCKET_NAME/${DOCKER_INFLUXDB_INIT_BUCKET}/g" \
            "$task_file" > /tmp/${base}.flux

        # Extract task name
        TASK_NAME=$(sed -n 's/.*name:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/${base}.flux | head -1)

        # Look up existing task ID by name
        TASK_ID=$(influx task list ${INFLUX_COMMON} --org ${DOCKER_INFLUXDB_INIT_ORG} \
            | grep "${TASK_NAME}" | awk '{print $1}') || true

        if [ -n "$TASK_ID" ]; then
            echo "Updating task ${TASK_NAME} (${TASK_ID})..."
            influx task update --id ${TASK_ID} --file /tmp/${base}.flux ${INFLUX_COMMON} \
                || echo "Failed to update task ${TASK_NAME}"
        else
            echo "Creating task ${TASK_NAME}..."
            influx task create --org ${DOCKER_INFLUXDB_INIT_ORG} --file /tmp/${base}.flux ${INFLUX_COMMON} \
                || echo "Task ${TASK_NAME} already exists"
        fi
    done
fi

echo "InfluxDB initialization complete!"

# Bring InfluxDB to foreground
wait $INFLUX_PID

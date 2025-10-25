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

# Start InfluxDB in the background
influxd &
INFLUX_PID=$!

# Wait for InfluxDB to be ready
echo "Waiting for InfluxDB to start..."
for i in {1..30}; do
    if influx ping --host http://localhost:${DOCKER_INFLUXDB_INIT_PORT} &>/dev/null; then
        echo "InfluxDB is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Check if InfluxDB needs initial setup
# The /api/v2/setup endpoint returns {"allowed":false} if already initialized
SETUP_ALLOWED=$(curl -s http://localhost:${DOCKER_INFLUXDB_INIT_PORT}/api/v2/setup | grep -o '"allowed":[^,}]*' | cut -d':' -f2 | tr -d ' ')

if [ "$SETUP_ALLOWED" = "false" ]; then
    echo "InfluxDB already initialized. Skipping setup..."
else
    # Conducts initial InfluxDB setup using the CLI
    echo "Setting up InfluxDB..."
    influx setup --skip-verify \
        --bucket    ${DOCKER_INFLUXDB_INIT_BUCKET} \
        --retention ${DOCKER_INFLUXDB_INIT_RETENTION} \
        --token     ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN} \
        --org       ${DOCKER_INFLUXDB_INIT_ORG} \
        --username  ${DOCKER_INFLUXDB_INIT_USERNAME} \
        --password  ${DOCKER_INFLUXDB_INIT_PASSWORD} \
        --host      http://localhost:${DOCKER_INFLUXDB_INIT_PORT} \
        --force

    # Create downsampling buckets
    echo "Creating downsampling buckets..."
    influx bucket create \
        --name "${DOCKER_INFLUXDB_INIT_BUCKET}_20s" \
        --org ${DOCKER_INFLUXDB_INIT_ORG} \
        --retention 1d \
        --token ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN} \
        --host http://localhost:${DOCKER_INFLUXDB_INIT_PORT} || echo "Bucket _20s already exists"

    influx bucket create \
        --name "${DOCKER_INFLUXDB_INIT_BUCKET}_1min" \
        --org ${DOCKER_INFLUXDB_INIT_ORG} \
        --retention 7d \
        --token ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN} \
        --host http://localhost:${DOCKER_INFLUXDB_INIT_PORT} || echo "Bucket _1min already exists"

    # Create downsampling tasks
    echo "Creating downsampling tasks..."
    if [ -f /influxdb/task_20s.flux ]; then
        # Substitute bucket and org names in task file
        sed -e "s/INIT_ORG_NAME/${DOCKER_INFLUXDB_INIT_ORG}/g" \
            -e "s/INIT_BUCKET_NAME_20s/${DOCKER_INFLUXDB_INIT_BUCKET}_20s/g" \
            -e "s/INIT_BUCKET_NAME/${DOCKER_INFLUXDB_INIT_BUCKET}/g" \
            /influxdb/task_20s.flux > /tmp/task_20s.flux
        
        influx task create \
            --org ${DOCKER_INFLUXDB_INIT_ORG} \
            --token ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN} \
            --file /tmp/task_20s.flux \
            --host http://localhost:${DOCKER_INFLUXDB_INIT_PORT} || echo "Task 20s already exists"
    fi

    if [ -f /influxdb/task_1min.flux ]; then
        # Substitute bucket and org names in task file
        sed -e "s/INIT_ORG_NAME/${DOCKER_INFLUXDB_INIT_ORG}/g" \
            -e "s/INIT_BUCKET_NAME_1min/${DOCKER_INFLUXDB_INIT_BUCKET}_1min/g" \
            -e "s/INIT_BUCKET_NAME_20s/${DOCKER_INFLUXDB_INIT_BUCKET}_20s/g" \
            /influxdb/task_1min.flux > /tmp/task_1min.flux
        
        influx task create \
            --org ${DOCKER_INFLUXDB_INIT_ORG} \
            --token ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN} \
            --file /tmp/task_1min.flux \
            --host http://localhost:${DOCKER_INFLUXDB_INIT_PORT} || echo "Task 1min already exists"
    fi
fi

echo "InfluxDB initialization complete!"

# Bring InfluxDB to foreground
wait $INFLUX_PID

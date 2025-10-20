#!/bin/bash
set -e

# Create provisioning directory if it doesn't exist
mkdir -p /etc/grafana/provisioning/datasources

# Substitute environment variables in datasource config using sed
sed -e "s|\${DOCKER_INFLUXDB_INIT_HOST}|${DOCKER_INFLUXDB_INIT_HOST}|g" \
    -e "s|\${DOCKER_INFLUXDB_INIT_PORT}|${DOCKER_INFLUXDB_INIT_PORT}|g" \
    -e "s|\${DOCKER_INFLUXDB_INIT_ORG}|${DOCKER_INFLUXDB_INIT_ORG}|g" \
    -e "s|\${DOCKER_INFLUXDB_INIT_BUCKET}|${DOCKER_INFLUXDB_INIT_BUCKET}|g" \
    -e "s|\${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}|${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}|g" \
    /grafana/provisioning/datasources/influxdb.yml.template > /etc/grafana/provisioning/datasources/influxdb.yml

# Start Grafana
exec /run.sh

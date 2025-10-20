#!/bin/bash
set -e

# Create dashboards directory
mkdir -p /var/lib/grafana/dashboards

# Substitute environment variables in datasource config
sed -e "s|\${DOCKER_INFLUXDB_INIT_HOST}|${DOCKER_INFLUXDB_INIT_HOST}|g" \
    -e "s|\${DOCKER_INFLUXDB_INIT_PORT}|${DOCKER_INFLUXDB_INIT_PORT}|g" \
    -e "s|\${DOCKER_INFLUXDB_INIT_ORG}|${DOCKER_INFLUXDB_INIT_ORG}|g" \
    -e "s|\${DOCKER_INFLUXDB_INIT_BUCKET}|${DOCKER_INFLUXDB_INIT_BUCKET}|g" \
    -e "s|\${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}|${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}|g" \
    /grafana/provisioning/datasources/influxdb.yml.template > /etc/grafana/provisioning/datasources/influxdb.yml

# Copy dashboard provider config
cp /grafana/provisioning/dashboards/dashboard-provider.yml /etc/grafana/provisioning/dashboards/

# Substitute bucket name in dashboard JSON and place in writable directory
sed -e "s|changeme|${DOCKER_INFLUXDB_INIT_BUCKET}|g" \
    /grafana/provisioning/dashboards/system-metrics.json > /var/lib/grafana/dashboards/system-metrics.json

# Start Grafana
exec /run.sh

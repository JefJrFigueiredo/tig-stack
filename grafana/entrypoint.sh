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

# Substitute bucket names in dashboard JSON and place in writable directory
sed -e "s/INIT_BUCKET_NAME/${DOCKER_INFLUXDB_INIT_BUCKET}/g" \
    /grafana/provisioning/dashboards/system-metrics.json > /var/lib/grafana/dashboards/system-metrics.json

# Merge any extra panel files from dashboards.d/ into the panels array
if [ -d /grafana/dashboards.d ] && ls /grafana/dashboards.d/*.json >/dev/null 2>&1; then
  DASHBOARD=/var/lib/grafana/dashboards/system-metrics.json
  for panel_file in /grafana/dashboards.d/*.json; do
    # Substitute bucket/org placeholders in panel file
    tmp_panel="/tmp/$(basename "$panel_file")"
    sed -e "s/INIT_BUCKET_NAME/${DOCKER_INFLUXDB_INIT_BUCKET}/g" \
        -e "s/INIT_ORG_NAME/${DOCKER_INFLUXDB_INIT_ORG}/g" "$panel_file" > "$tmp_panel"
    # Insert panel before the last ] (end of panels array), reading from file to preserve escaping
    awk -v pfile="$tmp_panel" '
      /\]/ { last_bracket = NR }
      { lines[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          if (i == last_bracket) {
            printf "    ,\n"
            while ((getline line < pfile) > 0) print line
          }
          print lines[i]
        }
      }
    ' "$DASHBOARD" > "${DASHBOARD}.tmp" && mv "${DASHBOARD}.tmp" "$DASHBOARD"
    rm -f "$tmp_panel"
  done
fi

# Start Grafana
exec /run.sh

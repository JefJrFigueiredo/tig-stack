
![Logo](https://user-images.githubusercontent.com/64506580/159311466-f720a877-6c76-403a-904d-134addbd6a86.png)


# Telegraf, InfluxDB, Grafana (TIG) Stack

Gain the ability to analyze and monitor telemetry data by deploying the TIG stack within minutes using [Docker](https://docs.docker.com/engine/install/) and [Docker Compose](https://docs.docker.com/compose/install/).




## ⚡️ Getting Started

Clone the project

```bash
git clone https://github.com/huntabyte/tig-stack.git
```

Navigate to the project directory

```bash
cd tig-stack
```

Run this command to create the .env file and generate a new admin token for InfluxDB:

```bash
[ ! -f .env ] && cp .env.example .env
var="DOCKER_INFLUXDB_INIT_ADMIN_TOKEN" \
&& new_token=$(openssl rand -hex 32) \
&& grep -q "^${var}=" .env \
&& sed -i "s/^${var}=.*/${var}=$new_token/" .env \
|| echo "${var}=$new_token" >> .env
```

(Optional) Change the environment variables define in `.env` that are used to setup and deploy the stack
```bash
├── influxdb/
│   ├── entrypoint.sh
├── telegraf/
│   ├── telegraf.conf
├── .env         <---
├── docker-compose.yml
└── ...
```

(Optional) Customize the `telegraf.conf` file which will be mounted to the container as a persistent volume

```bash
├── influxdb/
│   ├── entrypoint.sh
├── telegraf/
│   ├── telegraf.conf <---
├── .env
├── docker-compose.yml
└── ...
```

Start the services
```bash
docker compose up -d
```

Access the Grafana portal in http://localhost:3000 (or the GRAFANA_PORT you set in the .env file), authenticate with login: `admin` and password: `admin` , change the password, go to Dashboards > System metrics and see the metrics in real-time. 

## Docker Images Used (Official & Verified)

[**Telegraf**](https://hub.docker.com/_/telegraf) / `1.38.2-alpine`

[**InfluxDB**](https://hub.docker.com/_/influxdb) / `2.8.0-alpine`

[**Grafana-OSS**](https://hub.docker.com/r/grafana/grafana-oss) / `12.4.2`


## Downsampling Strategy — Store Data Forever

Most monitoring stacks keep raw data for a few days and then throw everything away. This project takes a different approach: **data is never fully discarded**. Instead, it passes through a cascade of downsampling tiers, each aggregating a wider window than the last, so older data occupies progressively less space while still remaining queryable at a meaningful resolution.

Each tier runs an InfluxDB task that reads from the previous bucket, computes `mean`, `min`, and `max` per field, and writes the result into the next bucket. The three variants allow Grafana to render a shaded min/max band around the mean line, preserving the sense of variability even in heavily aggregated data.

Grafana automatically selects the right bucket based on the age of the queried time range — no configuration needed.

| Frequency | Retention | Samples at boundary |
|-----------|-----------|---------------------|
| 5s        | 3h        | ~2160               |
| 1m        | 36h       | ~2160               |
| 5m        | 7d        | ~2016               |
| 1h        | 90d       | ~2160               |
| 4h        | 1y        | ~2190               |
| 1d        | 6y        | ~2190               |
| 1w        | forever   | —                   |

The *samples at boundary* column shows how many data points Grafana receives when viewing exactly the full retention window of that tier — kept deliberately close to ~2000, which matches the pixel resolution of a typical dashboard panel. Going higher would waste bandwidth and rendering time; going lower would lose visible detail.

The weekly bucket has no retention limit. A system running continuously for decades will always have its full history available, compressed into one point per week per metric.

## Contributing

Contributions are always welcome!



![Logo](https://user-images.githubusercontent.com/64506580/159311466-f720a877-6c76-403a-904d-134addbd6a86.png)


# Telegraf, InfluxDB, Grafana (TIG) Stack

Gain the ability to analyze and monitor telemetry data by deploying the TIG stack within minutes using [Docker](https://docs.docker.com/engine/install/) and [Docker Compose](https://docs.docker.com/compose/install/).




## ⚡️ Getting Started

Clone the project

```bash
git clone https://github.com/jefjrfigueiredo/tig-stack.git
```

Navigate to the project directory

```bash
cd tig-stack
```

Convenience command to start everything in one single step:

```bash
[ ! -f .env ] && cp .env.example .env; \
var="DOCKER_INFLUXDB_INIT_ADMIN_TOKEN" \
&& new_token=$(openssl rand -hex 32) \
&& grep -q "^${var}=" .env \
&& sed -i "s/^${var}=.*/${var}=$new_token/" .env \
|| echo "${var}=$new_token" >> .env \
&& docker compose up -d
```

Change the environment variables define in `.env` that are used to setup and deploy the stack
```bash
├── telegraf/
├── .env         <---
├── docker-compose.yml
├── entrypoint.sh
└── ...
```

Customize the `telegraf.conf` file which will be mounted to the container as a persistent volume

```bash
├── telegraf/
│   ├── telegraf.conf <---
├── .env
├── docker-compose.yml
├── entrypoint.sh
└── ...
```

Start the services
```bash
docker compose up -d
```
## Docker Images Used (Official & Verified)

[**Telegraf**](https://hub.docker.com/_/telegraf) / `1.19`

[**InfluxDB**](https://hub.docker.com/_/influxdb) / `2.1.1`

[**Grafana-OSS**](https://hub.docker.com/r/grafana/grafana-oss) / `8.4.3`



## Contributing

Contributions are always welcome!


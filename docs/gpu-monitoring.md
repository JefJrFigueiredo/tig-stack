# GPU Monitoring

GPU monitoring is hardware- and OS-specific. Configuration lives in override files that are **gitignored** — each user creates them locally.

GPU monitoring uses the drop-in override convention documented in `CLAUDE.md` — all override files are gitignored by default.

## NVIDIA — Native Linux

1. Ensure `nvidia-smi` is installed on the host (`nvidia-utils` package).
2. Requires [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) on the host.
3. Create `docker-compose.override.yml`:
   ```yaml
   services:
     telegraf:
       volumes:
         - ./telegraf/telegraf.d:/etc/telegraf/telegraf.d:ro
       deploy:
         resources:
           reservations:
             devices:
               - driver: nvidia
                 count: all
                 capabilities: [gpu, utility]

     grafana:
       volumes:
         - ./grafana/dashboards.d:/grafana/dashboards.d:ro
   ```
4. Create `telegraf/telegraf.d/nvidia.conf`:
   ```toml
   [[inputs.nvidia_smi]]
   ```
5. `docker compose down && docker compose up -d`

## NVIDIA — WSL2

Same as Native Linux, but the override must also switch to a Debian image (WSL2's `nvidia-smi` is glibc-linked) and mount the WSL library directory.

1. Ensure [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) is installed.
2. Create `docker-compose.override.yml`:
   ```yaml
   services:
     telegraf:
       image: telegraf:1.38.2
       volumes:
         - /usr/lib/wsl:/usr/lib/wsl:ro
         - ./telegraf/telegraf.d:/etc/telegraf/telegraf.d:ro
       environment:
         - LD_LIBRARY_PATH=/usr/lib/wsl/lib
         - PATH=/usr/lib/wsl/lib:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
       deploy:
         resources:
           reservations:
             devices:
               - driver: nvidia
                 count: all
                 capabilities: [gpu, utility]

     grafana:
       volumes:
         - ./grafana/dashboards.d:/grafana/dashboards.d:ro
   ```
3. Create `telegraf/telegraf.d/nvidia-wsl2.conf`:
   ```toml
   [[inputs.nvidia_smi]]
     bin_path = "/usr/lib/wsl/lib/nvidia-smi"
   ```
4. `docker compose down && docker compose up -d`

## AMD

1. Ensure `rocm-smi` is installed on the host.
2. Create `docker-compose.override.yml`:
   ```yaml
   services:
     telegraf:
       devices:
         - /dev/kfd
         - /dev/dri

     grafana:
       volumes:
         - ./grafana/dashboards.d:/grafana/dashboards.d:ro
   ```
3. Create `telegraf/telegraf.d/amd.conf`:
   ```toml
   [[inputs.amd_rocm_smi]]
   ```
4. `docker compose down && docker compose up -d`

## String field exclusion

GPU plugins produce string fields that break numeric aggregation. NVIDIA string fields (`name`, `compute_mode`, `uuid`, `pstate`, `driver_version`, `cuda_version`, `display_active`, `display_mode`, `vbios_version`) are already excluded in `task_1min.flux` — the filters are a no-op when GPU monitoring is disabled.

For AMD, check `rocm-smi` output for string fields and add similar exclusions to `getBase()` in `task_1min.flux`.

## Grafana dashboard

The provisioned `system-metrics.json` does not include a GPU panel (not everyone has a GPU). The entrypoint merges any `.json` files from `grafana/dashboards.d/` into the panels array at startup — no manual UI setup needed.

### NVIDIA panel

Create `grafana/dashboards.d/gpu-nvidia.json` with a panel object querying measurement `nvidia_smi`, field `utilization_gpu` (0–100%). The panel should follow the same mean/min/max band pattern as CPU/Memory:

- **3 queries** (A/B/C): same bucket-selection preamble, field `utilization_gpu` / `utilization_gpu_mean|max|min`, aggregation `fn: mean|max|min`, output field `gpu_mean|max|min`
- **Field config**: unit = percent, min = 0, max = 100
- **Overrides**: `gpu_mean` lineWidth 2, `gpu_max` lineWidth 1 + fillBelowTo `gpu_min` + fillOpacity 20, `gpu_min` lineWidth 1

Use `INIT_BUCKET_NAME` placeholders — the entrypoint substitutes them automatically.

See the existing panels in `system-metrics.json` for the exact query structure. For AMD, substitute measurement `amd_rocm_smi` and field `gpu_busy_percent`.


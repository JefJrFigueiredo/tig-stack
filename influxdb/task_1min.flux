option task = {
  name: "downsample-all-to-1min",
  every: 1m,
  offset: 10s
}

// All measurements except net (which has cumulative counters needing derivative)
getBase = () =>
  from(bucket: "INIT_BUCKET_NAME")
    |> range(start: -task.every)
    |> filter(fn: (r) => r["_measurement"] != "" and r["_field"] != "")
    |> filter(fn: (r) => r["_field"] != "uptime_format")
    // Exclude NVIDIA GPU string fields that break numeric aggregation (no-op if GPU monitoring is disabled)
    |> filter(fn: (r) => r["_field"] != "name" and r["_field"] != "compute_mode"
       and r["_field"] != "uuid" and r["_field"] != "pstate"
       and r["_field"] != "driver_version" and r["_field"] != "cuda_version"
       and r["_field"] != "display_active" and r["_field"] != "display_mode"
       and r["_field"] != "vbios_version")
    |> filter(fn: (r) => r["_measurement"] != "net")

// Net bytes_sent/bytes_recv converted to bytes/sec via derivative.
// Queries -2m to ensure a preceding point is available for the derivative
// at the start of the -1m window; tail(n:1) keeps only the current window.
getNetRate = () =>
  from(bucket: "INIT_BUCKET_NAME")
    |> range(start: -2m)
    |> filter(fn: (r) => r["_measurement"] == "net")
    |> filter(fn: (r) => r["_field"] == "bytes_sent" or r["_field"] == "bytes_recv")
    |> filter(fn: (r) => r["interface"] != "lo")
    |> derivative(unit: 1s, nonNegative: true)

mean_data = getBase()
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false, offset: 0s)
  |> map(fn: (r) => ({ r with _field: r._field + "_mean" }))

min_data = getBase()
  |> aggregateWindow(every: 1m, fn: min, createEmpty: false, offset: 0s)
  |> map(fn: (r) => ({ r with _field: r._field + "_min" }))

max_data = getBase()
  |> aggregateWindow(every: 1m, fn: max, createEmpty: false, offset: 0s)
  |> map(fn: (r) => ({ r with _field: r._field + "_max" }))

mean_net = getNetRate()
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false, offset: 0s)
  |> tail(n: 1)
  |> map(fn: (r) => ({ r with _field: r._field + "_mean" }))

min_net = getNetRate()
  |> aggregateWindow(every: 1m, fn: min, createEmpty: false, offset: 0s)
  |> tail(n: 1)
  |> map(fn: (r) => ({ r with _field: r._field + "_min" }))

max_net = getNetRate()
  |> aggregateWindow(every: 1m, fn: max, createEmpty: false, offset: 0s)
  |> tail(n: 1)
  |> map(fn: (r) => ({ r with _field: r._field + "_max" }))

union(tables: [mean_data, min_data, max_data, mean_net, min_net, max_net])
  |> to(bucket: "INIT_BUCKET_NAME_1min", org: "INIT_ORG_NAME")

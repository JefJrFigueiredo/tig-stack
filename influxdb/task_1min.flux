option task = {
  name: "downsample-all-to-1min",
  every: 1m,
  offset: 10s
}

from(bucket: "changeme_20s")
  |> range(start: -task.every)
  |> filter(fn: (r) => r["_measurement"] != "" and r["_field"] != "")
  |> filter(fn: (r) => r["_field"] != "uptime_format")
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
  |> to(bucket: "changeme_1min", org: "changeme")

option task = {
  name: "downsample-all-to-20s",
  every: 20s,
  offset: 5s
}

from(bucket: "changeme")
  |> range(start: -task.every)
  |> filter(fn: (r) => r["_measurement"] != "" and r["_field"] != "")
  |> filter(fn: (r) => r["_field"] != "uptime_format")
  |> aggregateWindow(every: 20s, fn: mean, createEmpty: false)
  |> to(bucket: "changeme_20s", org: "changeme")

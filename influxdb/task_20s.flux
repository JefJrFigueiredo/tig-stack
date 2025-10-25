option task = {
  name: "downsample-all-to-20s",
  every: 20s,
  offset: 5s
}

from(bucket: "INIT_BUCKET_NAME")
  |> range(start: -task.every)
  |> filter(fn: (r) => r["_measurement"] != "" and r["_field"] != "")
  |> filter(fn: (r) => r["_field"] != "uptime_format")
  |> aggregateWindow(every: 20s, fn: mean, createEmpty: false, offset: 0s)
  |> to(bucket: "INIT_BUCKET_NAME_20s", org: "INIT_ORG_NAME")

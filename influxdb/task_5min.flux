import "strings"

option task = {
  name: "downsample-all-to-5min",
  every: 5m,
  offset: 30s
}

getBase = () =>
  from(bucket: "INIT_BUCKET_NAME_1min")
    |> range(start: -task.every)
    |> filter(fn: (r) => r["_measurement"] != "" and r["_field"] != "")

mean_data = getBase()
  |> filter(fn: (r) => strings.hasSuffix(v: r._field, suffix: "_mean"))
  |> aggregateWindow(every: 5m, fn: mean, createEmpty: false, offset: 0s)

min_data = getBase()
  |> filter(fn: (r) => strings.hasSuffix(v: r._field, suffix: "_min"))
  |> aggregateWindow(every: 5m, fn: min, createEmpty: false, offset: 0s)

max_data = getBase()
  |> filter(fn: (r) => strings.hasSuffix(v: r._field, suffix: "_max"))
  |> aggregateWindow(every: 5m, fn: max, createEmpty: false, offset: 0s)

union(tables: [mean_data, min_data, max_data])
  |> to(bucket: "INIT_BUCKET_NAME_5min", org: "INIT_ORG_NAME")

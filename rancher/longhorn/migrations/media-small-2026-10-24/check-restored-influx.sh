#!/bin/sh
set -eu
state=/target/influxdb
influxd inspect verify-tsm --engine-path "$state/engine"
influxd inspect verify-wal --wal-path "$state/engine/wal"
influxd inspect verify-seriesfile --data-path "$state/engine/data"
# No Scrutiny server, collector, scheduled Influx tasks, service or ingress.
influxd --bolt-path "$state/influxd.bolt" --sqlite-path "$state/influxd.sqlite" \
  --engine-path "$state/engine" --http-bind-address 127.0.0.1:18086 \
  --no-tasks --reporting-disabled --log-level error >/tmp/restore-influxd.log 2>&1 &
influx_pid=$!
trap 'kill -TERM "$influx_pid" 2>/dev/null || true; wait "$influx_pid" 2>/dev/null || true' EXIT INT TERM
for attempt in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:18086/health >/tmp/influx-health.json 2>/dev/null; then
    grep -Eq '"status"[[:space:]]*:[[:space:]]*"pass"' /tmp/influx-health.json
    curl -fsS http://127.0.0.1:18086/api/v2/setup >/tmp/influx-setup.json
    grep -Eq '"allowed"[[:space:]]*:[[:space:]]*false' /tmp/influx-setup.json
    echo 'Restored InfluxDB: offline checks passed; health pass; existing initialized metadata loaded'
    exit 0
  fi
  if ! kill -0 "$influx_pid" 2>/dev/null; then
    echo 'Restored InfluxDB exited before health passed; inspect private startup log' >&2
    exit 1
  fi
  sleep 1
done
echo "Restored InfluxDB health timed out after $attempt attempts" >&2
exit 1

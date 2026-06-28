#!/usr/bin/env bash
# One-shot loader (runs as the `loader` service in docker-compose.hub.yml).
# Waits for the cluster, then creates the schema (RF=3) and bulk-loads the
# baked-in edges ONCE. Idempotent: re-running skips if the data is already there.
set -e
HOST="${CASSANDRA_HOST:-cas1}"

echo "[loader] waiting for CQL on ${HOST} ..."
until cqlsh "$HOST" -e "DESCRIBE CLUSTER" >/dev/null 2>&1; do sleep 5; done

if cqlsh "$HOST" -e "SELECT id FROM twitter.edges LIMIT 1" >/dev/null 2>&1; then
  echo "[loader] edges already present - nothing to do."
  exit 0
fi

echo "[loader] creating schema (RF=3) ..."
cqlsh "$HOST" -f /opt/ids/schema.cql

echo "[loader] bulk-loading edges1.json ..."
/opt/dsbulk/bin/dsbulk load -url /opt/ids/edges1.json -k twitter -t edges \
  -h "$HOST" -c json --connector.json.mode SINGLE_DOCUMENT

echo "[loader] done."

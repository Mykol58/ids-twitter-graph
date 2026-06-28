#!/usr/bin/env bash
# Build (and optionally push) the self-loading Cassandra image.
#
# Usage:
#   ./build_image.sh <tag>          # build only
#   ./build_image.sh <tag> --push   # build then push (requires `docker login`)
# e.g. ./build_image.sh youruser/ids-twitter-cassandra:latest --push
set -euo pipefail
cd "$(dirname "$0")"                      # cassandra/image
TAG="${1:-ids-twitter-cassandra:latest}"

# dsbulk + the data are NOT committed; copy them into the build context.
[ -x ../dsbulk/bin/dsbulk ] || { echo "dsbulk missing -- run ../load_edges.sh once first"; exit 1; }
[ -f ../../Data/edges1.json ] || { echo "edges1.json missing under ../../Data"; exit 1; }

echo ">> assembling build context ..."
rm -rf dsbulk edges1.json
cp -r ../dsbulk ./dsbulk
cp ../../Data/edges1.json ./edges1.json

echo ">> building $TAG ..."
docker build -t "$TAG" .

echo ">> cleaning copied-in artifacts ..."
rm -rf dsbulk edges1.json

if [ "${2:-}" = "--push" ]; then
  echo ">> pushing $TAG ..."
  docker push "$TAG"
fi
echo ">> done: $TAG"

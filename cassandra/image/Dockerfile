# Cassandra image for the IDS project, used to stand up a 3-node / RF=3 cluster
# with the Twitter `edges` graph preloaded (see docker-compose.hub.yml).
#
# By DEFAULT the image behaves as a normal Cassandra node (stock entrypoint), so
# it is safe to run three of them. The baked-in loader (/opt/ids/load.sh) is run
# ONCE by the separate `loader` service to create the schema and load the data.
#
# Build context must contain (assembled by build_image.sh): dsbulk/ and edges1.json.
FROM cassandra:4.1

COPY dsbulk/ /opt/dsbulk/
COPY schema.cql /opt/ids/schema.cql
COPY edges1.json /opt/ids/edges1.json
COPY load.sh /opt/ids/load.sh
RUN chmod +x /opt/ids/load.sh /opt/dsbulk/bin/dsbulk

ENV CASSANDRA_CLUSTER_NAME="ids-twitter-graph"

# Lets docker-compose gate node startup on real readiness (no compose-side config).
HEALTHCHECK --interval=15s --timeout=10s --retries=30 --start-period=90s \
  CMD nodetool statusgossip | grep -q running && cqlsh -e "DESCRIBE CLUSTER" >/dev/null 2>&1 || exit 1

# ENTRYPOINT/CMD inherited from the base image == run as a normal Cassandra node.

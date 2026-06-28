# ids-twitter-cassandra

A Cassandra image for the IDS project that stands up a **3-node, replication-factor-3
cluster** with the Twitter **follow/follower graph (`edges`) preloaded** — 6,067
records. Everything needed (loader, schema, data) is baked into the image, so you
run it with **no edits and no extra files**.

- Cluster: `ids-twitter-graph` · 3 nodes · RF=3 (survives one node down at QUORUM)
- Keyspace `twitter`, table `edges (id bigint PK, follows list<bigint>, is_followed_by list<bigint>)`
- Stores **only** the `edges` graph.

---

## Run the full 3-node cluster (recommended)

Save the compose below as `docker-compose.yml` and start it:

```bash
docker compose up -d
```

```yaml
name: ids-twitter-cassandra

x-node: &node
  image: mikelez/ids-twitter-cassandra:latest
  environment: &node-env
    CASSANDRA_CLUSTER_NAME: "ids-twitter-graph"
    CASSANDRA_SEEDS: "cas1"
    CASSANDRA_ENDPOINT_SNITCH: GossipingPropertyFileSnitch
    CASSANDRA_DC: datacenter1
    MAX_HEAP_SIZE: "512M"
    HEAP_NEWSIZE: "128M"
  mem_limit: 1500m

services:
  cas1:
    <<: *node
    container_name: cas1
    hostname: cas1
    ports: ["9042:9042"]
    volumes: ["cas1_data:/var/lib/cassandra"]
  cas2:
    <<: *node
    container_name: cas2
    hostname: cas2
    depends_on: { cas1: { condition: service_healthy } }
    volumes: ["cas2_data:/var/lib/cassandra"]
  cas3:
    <<: *node
    container_name: cas3
    hostname: cas3
    depends_on: { cas2: { condition: service_healthy } }
    volumes: ["cas3_data:/var/lib/cassandra"]
  loader:
    image: mikelez/ids-twitter-cassandra:latest
    container_name: ids-loader
    depends_on: { cas3: { condition: service_healthy } }
    environment: { CASSANDRA_HOST: cas1 }
    entrypoint: ["/opt/ids/load.sh"]
    healthcheck: { disable: true }
    restart: "no"

volumes:
  cas1_data:
  cas2_data:
  cas3_data:
```

**Startup takes a few minutes**: nodes join one at a time (cas1 → cas2 → cas3),
then the `loader` creates the schema and loads the edges and exits. Watch it with:

```bash
docker compose logs -f loader      # wait for "[loader] done."
```

## Verify

```bash
docker exec cas1 nodetool status twitter                       # 3 nodes, all "UN"
docker exec cas1 cqlsh -e "SELECT COUNT(*) FROM twitter.edges;" # -> 6067
# survives one node down at QUORUM:
docker stop cas3
docker exec cas1 cqlsh -e "CONSISTENCY QUORUM; SELECT COUNT(*) FROM twitter.edges;"  # -> 6067
docker start cas3
```

## Query

```bash
docker exec -it cas1 cqlsh
```
```sql
USE twitter;
SELECT * FROM edges WHERE id = 5660312;   -- a user's follows / followers lists
```

External clients/BI tools connect on **`localhost:9042`** (native protocol). For
Superset, go via PrestoDB/Trino with a Cassandra catalog pointing at `cas1:9042`.

## Stop

```bash
docker compose down       # stop, keep data (volumes persist)
docker compose down -v    # stop and wipe data
```

---

### Notes
- The image runs as a normal Cassandra node by default, so it is safe to run
  three of them. The loader is a separate one-shot service.
- Pull directly if you want just the image: `docker pull mikelez/ids-twitter-cassandra:latest`
- 512 MB heap per node (~2.5 GB total) so the cluster fits on a typical laptop.

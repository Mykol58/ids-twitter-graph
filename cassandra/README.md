# Cassandra storage — Twitter `edges` graph

Cassandra component of the IDS 2025-26 project. It stores the Twitter
**follow/follower graph (`edges`)** in a **3-node, replication-factor-3** cluster.
Cassandra holds **`edges` and nothing else**, and `edges` is stored **only here**
(single source of truth). Where the other source files (`users`, `mbti_labels`,
tweets) are stored is decided elsewhere in the project.

The cluster runs from a **single, data-free `docker-compose.yml`**: the schema,
loader and data are baked into the published image
[`mikelez/ids-twitter-cassandra`](https://hub.docker.com/r/mikelez/ids-twitter-cassandra),
so there are no data files in this folder and nothing to edit.

## Why Cassandra
`edges` is **not tabular**: each user has two variable-length lists
(`follows`, `is_followed_by`). Cassandra's `list<bigint>` columns model that
directly — the justification for choosing it over a relational table.

## Run
```bash
docker compose up -d
docker compose logs -f loader      # wait for "[loader] done.", then Ctrl-C
```
Startup takes a few minutes: the nodes join one at a time (`cas1` → `cas2` →
`cas3`), then the one-shot `loader` creates the schema and bulk-loads the 6,067
edges and exits (`ids-loader  Exited (0)` is success).

## Verify
```bash
docker exec cas1 nodetool status twitter                        # 3 nodes, all "UN", RF=3
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
Schema: keyspace `twitter`, table `edges (id bigint PK, follows list<bigint>, is_followed_by list<bigint>)`.

## Stop
```bash
docker compose down       # stop, keep data (volumes persist)
docker compose down -v    # stop and wipe data
```

## Role in the project & BI link
Project.docx notes Cassandra has no easy Superset integration and must be
connected **using PrestoDB**. The BI path is:
`Cassandra (twitter.edges) → PrestoDB Cassandra catalog (cas1:9042) → Superset`.
This is implemented in **[`../bi/`](../bi/README.md)** (Presto + Superset compose,
pre-wired to this cluster's network). Bring this cluster up first, then `../bi`.
For the report, capture the `nodetool status` output and a Superset chart built
on `twitter.edges` (joined with another source for the "multiple data sources"
figure).

## How the image is built
`image/` contains the sources to (re)build and publish the image — `Dockerfile`,
`load.sh`, `schema.cql` (RF=3), `build_image.sh`, and `image/README.md`. The data
(`edges1.json`) and `dsbulk` are pulled in only at build time and are **not**
committed. To rebuild/push:
```bash
cd image && ./build_image.sh mikelez/ids-twitter-cassandra:latest --push
```

## Submission notes (Project.docx)
- The zip is a **single `docker-compose.yml`** (+ this README and the `image/`
  build sources) — **one yaml file, no data files**.
- `docker compose up -d` is the only launch step; container count is kept minimal
  (3 nodes + a transient loader).
- Config/program files are commented, as the doc says is appreciated.

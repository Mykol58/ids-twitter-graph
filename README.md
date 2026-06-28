# IDS 2025-26 — Twitter graph: storage & visualization

Course project for *Infrastructures for Data Science (IDS)*. It stores a Twitter
**follow/follower graph** in a distributed **Apache Cassandra** cluster and
visualizes it in **Apache Superset**, bridged by **PrestoDB** (Superset has no
native Cassandra connector).

```
                 ┌──────────────────────┐      ┌───────────┐      ┌────────────┐
   edges1.json → │  Cassandra cluster   │  →   │  PrestoDB │  →   │  Superset  │
   (6,067 rows)  │  3 nodes · RF=3      │ SQL  │  :8080    │ SQL  │  :8088     │
                 │  keyspace twitter    │      │  catalog  │      │  charts &  │
                 │  table   edges       │      │ cassandra │      │ dashboards │
                 └──────────────────────┘      └───────────┘      └────────────┘
```

The project is split into two self-contained modules, each with its own README:

| Module | What it does | Details |
|--------|--------------|---------|
| [`cassandra/`](cassandra/README.md) | 3-node / RF=3 Cassandra cluster storing the `edges` graph | [cassandra/README.md](cassandra/README.md) |
| [`bi/`](bi/README.md) | PrestoDB + Superset visualization layer | [bi/README.md](bi/README.md) |

---

## Quick start

**Prerequisites:** Docker + Docker Compose and ~7 GB of free RAM
(~2.5 GB Cassandra + ~4 GB Presto/Superset).

```bash
# 1) Storage: start Cassandra and load the edges
cd cassandra
docker compose up -d
docker compose logs -f loader      # wait for "[loader] done." (ids-loader Exited (0)), then Ctrl-C

# 2) Visualization: start Presto + Superset (must run cassandra first)
cd ../bi
docker compose up -d
docker compose logs -f superset    # wait until gunicorn "Booting worker", then Ctrl-C
```

Then open **http://localhost:8088** and log in with **`admin` / `admin`**.
The database connection and the `twitter.edges` dataset are pre-registered, so
you can go straight to **SQL Lab** or **Charts**. See
[bi/README.md](bi/README.md#3-visualize-the-data-in-superset) for a step-by-step
chart-building walkthrough.

> Order matters: the `cassandra` module creates the Docker network that the `bi`
> module attaches to, so always start `cassandra` first.

---

## The data model

Cassandra stores **only** the `edges` graph and nothing else; `edges` lives
**only** in Cassandra (single source of truth). Each row is one user:

```
keyspace twitter
table    edges ( id bigint PRIMARY KEY,
                 follows         list<bigint>,
                 is_followed_by  list<bigint> )
```

**Why Cassandra:** `edges` is not tabular — each user has two variable-length
lists. Cassandra's `list<bigint>` columns model that directly. **Why 3 nodes /
RF=3:** the data is tiny (~1 MiB per copy), so sizing is driven by fault
tolerance, not space — RF=3 across 3 nodes survives one node down at QUORUM, and
heaps are kept small (512 MB) so the cluster coexists with the rest of the stack.

The other source files (`users`, `mbti_labels`, tweets) are **not** part of this
Cassandra module; where they are stored is decided elsewhere in the project.

---

## Visualizing in Superset

Superset cannot read Cassandra directly (as Project.docx notes), so PrestoDB
exposes the cluster as SQL. In Superset the connection is:

```
presto://presto:8080/cassandra
```

and tables appear as `cassandra.twitter.edges`. From there you build charts in
the no-code builder or write SQL in SQL Lab — for example, the 10 most-followed
users, or a join against another data source (Presto allows joins that raw CQL
cannot). Full walkthrough and example queries:
[bi/README.md](bi/README.md#3-visualize-the-data-in-superset).

---

## Verify the whole pipeline

```bash
# Cassandra: cluster health and row count
docker exec cas1 nodetool status twitter                         # 3 nodes "UN", RF=3
docker exec cas1 cqlsh -e "SELECT COUNT(*) FROM twitter.edges;"  # -> 6067

# Presto -> Cassandra
docker exec presto presto-cli --server localhost:8080 \
  --catalog cassandra --schema twitter --execute "SELECT COUNT(*) FROM edges"  # -> 6067

# Superset -> Presto (the exact driver/URI Superset uses)
docker exec superset python -c "from sqlalchemy import create_engine; \
e=create_engine('presto://presto:8080/cassandra'); \
print(e.connect().exec_driver_sql('SELECT COUNT(*) FROM twitter.edges').fetchone())"
```

---

## Stop

```bash
cd bi        && docker compose down       # stop Presto + Superset
cd ../cassandra && docker compose down    # stop Cassandra (add -v to also wipe data)
```

---

## Repository layout & notes

```
IDS_project/
├── README.md                 ← this file
├── cassandra/                ← storage module (3-node RF=3 Cassandra)
│   ├── docker-compose.yml
│   ├── image/                ← sources to build the published image
│   └── README.md
├── bi/                       ← visualization module (Presto + Superset)
│   ├── docker-compose.yml
│   ├── presto/cassandra.properties
│   ├── superset/             ← Dockerfile + bootstrap
│   └── README.md
└── Data/                     ← source datasets (NOT in git, see below)
```

- **Data files are not committed.** `Data/` (incl. the 222 MB `tweets1.json`) and
  the downloaded `cassandra/dsbulk/` loader are git-ignored — they exceed
  GitHub's limits, the project rules say no data files in the submission, and the
  data should not be redistributed publicly. The Cassandra image already bakes in
  the `edges` data, so the stack runs with no local data files.
- Each module runs from a single `docker-compose.yml` with `docker compose up -d`,
  and config/program files are commented.

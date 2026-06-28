# BI / visualization — PrestoDB → Superset

This module visualizes the Twitter follow/follower graph (`twitter.edges`) that
lives in the Cassandra cluster. Apache Superset has **no native Cassandra
connector**, so — exactly as Project.docx requires — **PrestoDB** sits in the
middle and exposes Cassandra as plain SQL:

```
   Cassandra                 PrestoDB                    Superset
 (3 nodes, RF=3)        catalog "cassandra"          web UI :8088
 twitter.edges    →     SQL over :8080         →      charts & dashboards
```

It is based on the Anant tutorial *"Visualize Data from Cassandra in Superset"*,
adapted to this project's cluster and to the official PrestoDB image.

---

## 1. What's in here

| Path | What it is |
|------|-----------|
| `docker-compose.yml` | Brings up `presto` + `superset`, joined to the Cassandra network |
| `presto/cassandra.properties` | Presto catalog `cassandra` → contact points `cas1,cas2,cas3:9042` |
| `superset/Dockerfile` | `apache/superset` + the PyHive `presto://` driver |
| `superset/superset-bootstrap.sh` | First-boot: migrate DB, create admin, init, serve |

**presto** (`prestodb/presto`) serves on `:8080`. **superset**
(`apache/superset` + driver) serves on `:8088`. Superset here is a *lean
single-container demo* — it uses its built-in SQLite metadata DB and no
Celery/Redis. That is plenty to build and view charts; a production deploy would
add Postgres + Redis.

---

## 2. Run it

**Prerequisites:** Docker + Docker Compose, and ~4 GB free RAM for this layer
(Presto ~1 GB heap + Superset). The Cassandra cluster uses ~2.5 GB on top.

The Cassandra cluster must be up **first** — it creates the shared Docker network
that Presto attaches to:

```bash
# 1) start the database and wait until it has loaded the edges
cd ../cassandra
docker compose up -d
docker compose logs -f loader        # wait for "[loader] done." / Exited (0), then Ctrl-C

# 2) start the BI layer (first run also builds the Superset image, ~1 min)
cd ../bi
docker compose up -d
docker compose logs -f superset      # wait until gunicorn "Booting worker", then Ctrl-C
```

Superset takes ~1–2 min on first boot (DB migration + admin user + init).

Open **http://localhost:8088** and log in with **`admin` / `admin`**.

> The database connection **"Cassandra (via Presto)"** and the **`twitter.edges`**
> dataset are already registered (they persist in the `superset_home` volume), so
> you can jump straight to step 3.

---

## 3. Visualize the data in Superset

There are two ways to work: **SQL Lab** (write SQL, then turn a result into a
chart) and the **no-code chart builder** (start from the dataset). Both are shown.

### 3a. Explore with SQL Lab
1. Top menu → **SQL** → **SQL Lab**.
2. On the left, set **Database** = `Cassandra (via Presto)`, **Schema** = `twitter`,
   **See table schema** = `edges`.
3. Paste a query and click **Run**, e.g. the total number of users in the graph:
   ```sql
   SELECT COUNT(*) AS users FROM cassandra.twitter.edges;   -- 6067
   ```
   or the 10 most-followed users (the lists are stored as text, so we count list
   length by splitting on commas):
   ```sql
   SELECT id,
          cardinality(split(replace(replace(is_followed_by,'[',''),']',''),',')) AS followers
   FROM cassandra.twitter.edges
   WHERE is_followed_by <> '[]'
   ORDER BY followers DESC
   LIMIT 10;
   ```
4. Click **Create Chart** to send the result straight into the chart builder.

### 3b. Build a chart from the dataset (no code)
1. Top menu → **Charts** → **+ Chart**.
2. Choose dataset **`edges`** and a chart type, then **Create New Chart**.
3. Configure, then **Create Chart** / **Save**. Three quick examples:

   **A "Big Number" — total users in the graph**
   - Chart type: **Big Number**
   - Metric: **COUNT(\*)** → shows `6067`.

   **A bar chart — top 10 users by follower count**
   - Easiest via SQL Lab: run the "most-followed" query in 3a, **Create Chart**,
     pick **Bar Chart**, X-axis = `id`, Metric = `MAX(followers)` (or `followers`),
     **Row limit** = 10, sort descending.

   **A table — browse raw edges**
   - Chart type: **Table**, dataset `edges`, columns `id`, `follows`,
     `is_followed_by`, Row limit = 100.

### 3c. Put charts on a dashboard
**Dashboards** → **+ Dashboard** → drag your saved charts in → **Save**. This is
the figure to screenshot for the report.

### 3d. (Reference) add the connection by hand
If you ever start from a clean Superset, add the database yourself:

> **Settings → Database Connections → + Database → Presto**
> SQLAlchemy URI: `presto://presto:8080/cassandra` → **Test Connection** → **Connect**

Then **Datasets → + Dataset** → Database `Cassandra (via Presto)`, Schema
`twitter`, Table `edges`.

---

## 4. Verify the pipeline (smoke tests)

PrestoDB → Cassandra (CLI inside the Presto container):
```bash
docker exec presto presto-cli --server localhost:8080 \
  --catalog cassandra --schema twitter --execute "SHOW TABLES"                 # -> edges
docker exec presto presto-cli --server localhost:8080 \
  --catalog cassandra --schema twitter --execute "SELECT COUNT(*) FROM edges"  # -> 6067
```
Superset → Presto (the exact driver + URI Superset uses internally):
```bash
docker exec superset python -c "from sqlalchemy import create_engine; \
e=create_engine('presto://presto:8080/cassandra'); \
print(e.connect().exec_driver_sql('SELECT COUNT(*) FROM twitter.edges').fetchone())"
```
All of the above were run and pass (count = 6067).

---

## 5. Notes for the report
- `follows` / `is_followed_by` are Cassandra `list<bigint>`; Presto exposes them
  as text (JSON-like) columns. That is fine for charts — split on commas to count
  list length (see the "most-followed" query above).
- Presto's edge over raw CQL is **joins**. When a second source (e.g. users/mbti)
  is added as another Presto catalog, you can join it with `twitter.edges` in SQL
  Lab — that is the "multiple data sources" figure.
- Good screenshots for the PDF: the **Presto connection screen** (URI above), a
  **SQL Lab** result, and a **chart/dashboard** built on `edges`.

---

## 6. Stop / reset
```bash
docker compose down        # stop Presto + Superset, keep Superset metadata
docker compose down -v     # also wipe the Superset metadata volume (charts, connection)
```
Stopping this layer does **not** touch the Cassandra data — that lives in the
`../cassandra` volumes.

---

## Troubleshooting
| Symptom | Fix |
|---------|-----|
| `network ids-twitter-cassandra_default not found` | Start `../cassandra` first; it creates the network. |
| Superset login page won't load | First boot takes 1–2 min; watch `docker compose logs -f superset`. |
| Presto query errors "no nodes available" | Cassandra still starting; wait until all 3 nodes are `healthy`. |
| Test Connection fails in UI | Confirm URI is exactly `presto://presto:8080/cassandra` and Presto is `Up`. |

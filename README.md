CDC pipeline: PostgreSQL changes are captured in real time and written to Apache Iceberg tables on MinIO object storage.
dlt pipeline: `loader/` directory contains a second pipeline that generates synthetic analytics events and ingests them into Iceberg via [dlt](https://dlthub.com)

Trino as query engine to read Iceberg tables.

## Architecture
```
PostgreSQL (WAL)    --> OLake --> Iceberg   / MinIO <-- Trino
MinIO events source --> dlt Iceberg tables  / MinIO <-- Trino
```

| Component | Role |
|---|---|
| PostgreSQL 18 | Source database with logical replication enabled |
| OLake | CDC engine — reads WAL via replication slot, writes Iceberg |
| MinIO | S3-compatible object store hosting Iceberg data files |
| Trino | Distributed query engine - reads Iceberg tables from MinIO via JDBC catalog |

OLake uses a JDBC catalog (backed by the same PostgreSQL instance) to track Iceberg table metadata. Trino connects to the same JDBC catalog to discover and query those tables.


## Run
Create the `.env` file in `/docker` and run:
```bash
# Start the full stack and init Postgres
make up

make events # (terminal 1)
make ingest # (terminal 2)

# Tear down (containers + volumes)
make destroy
```
Run both terminals in parallel — `make ingest` polls every 5 seconds and picks up only files added since the last run (incremental by `modification_date`), so it processes batches as `make events` writes them. \
`make destroy` also resets `state.json` so the next `make up` performs a clean re-snapshot.

## Postgres CDC
PostgreSQL is started with `wal_level=logical`. `init.sql` creates a publication (`olake`) and a replication slot (`olake_slot`) on first boot. \
OLake connects via the replication slot, reads WAL changes, and writes them as Parquet files under `s3://iceberg/`. \
After each sync it commits the current Log Sequence Number (LSN) to `docker/olake/config/state.json` and immediately restarts to pick up new changes. \

⚠️
As OLake is batch-oriented (not long-running deamon), it reads all WAL changes accumulated since the last committed LSN, flushes them to Iceberg, then exits with code 0. \
However, as the `restart: always` policy in olake compose immediately relaunches it, a continuous polling loop is in place. Effective latency equals one sync cycle (few seconds).

### LSN mismatch after destroy
Destroying the stack without running `make destroy` (e.g. `docker volume rm` manually) make the LSN saved in `state.json` be ahead of the new PostgreSQL instance. OLake will refuse to sync with:
```
lsn mismatch, please proceed with clear destination
```

## OLake Configuration
| File | Purpose |
|---|---|
| `docker/olake/config/source.json` | PostgreSQL connection + CDC settings |
| `docker/olake/config/destination.json` | Iceberg writer + JDBC catalog + MinIO S3 settings |
| `docker/olake/config/catalog.json` | Selected streams (tables) and their schemas |
| `docker/olake/config/state.json` | Last committed LSN — do not edit manually |


### dlt Loader
| File | Role |
|---|---|
| `loader/events-engine.py` | Generates synthetic Segment-style events and writes JSONL batches to MinIO `s3://events/` |
| `loader/events-ingestion.py` | Polls `s3://events/` for new JSONL files (incremental) and loads them into an Iceberg table via dlt |
| `loader/constants.py` | Shared config — MinIO credentials, event types, user pool, batch settings |


## MinIO
Console available at [http://localhost:9001](http://localhost:9001) (default credentials: `admin` / `password`).

Iceberg data is written to the `iceberg` bucket under `postgres_pgsource_public/<table>/`.

## Trino
UI available at [http://localhost:8080](http://localhost:8080) \
SQL client: **Trino** connection to localhost 8080, database `iceberg`, any username and no password

```
SHOW SCHEMAS FROM iceberg;
SELECT * FROM iceberg.postgres_pgsource_public.companies;
SELECT * FROM iceberg.postgres_pgsource_public.invoices;
```

### Iceberg catalog
Trino connects to the Iceberg JDBC catalog stored in PostgreSQL (`pgsource`) tables:
1) Table: `iceberg_tables` - Purpose: One row per table
2) Table: `iceberg_namespace_properties` - Purpose: One row per namespace property (`postgres_pgsource_public`)

OLake registers tables under the catalog `olake_iceberg` (set in `iceberg.jdbc-catalog-name` in `iceberg.properties`). \
dlt registers tables under the catalog `olake_iceberg` (set in `iceberg_catalog_name    = "olake_iceberg"` in `secrets.toml`).

### Iceberg metadata layer
Iceberg splits metadata across two places:

1 - **Postgres (JDBC catalog)** - one row per table, just a pointer to latest metadata file:
```
catalog_name  | table_namespace           | table_name | metadata_location
olake_iceberg | postgres_pgsource_public  | companies  | s3://iceberg/postgres_pgsource_public/companies/metadata/00001-xxx.metadata.json
olake_iceberg | postgres_pgsource_public  | invoices   | s3://iceberg/postgres_pgsource_public/invoices/metadata/00001-zzz.metadata.json
olake_iceberg | events                    | events     | s3://iceberg/events/events/metadata/00007-kkk.metadata.json
```

2- **MinIO (metadata)** - the full Iceberg metadata (and data):
```
s3://iceberg/postgres_pgsource_public/companies/
|---metadata/
|     |--v1.metadata.json     <- schema, partition spec, snapshot history
|     |--snap-123.avro        <- manifest list
|     |--manifest-abc.avro    <- list of parquet data files
|---data/
      |--*.parquet            <- row data
```

### Iceberg events table
dlt ingests all JSONL files into a single Iceberg table with two partition columns:

| Partition | Column | Granularity |
|---|---|---|
| `day` | `timestamp` | one partition per calendar day |
| `identity` | `type` | one partition per event type (`track` / `identify` / `page`) |

Query from Trino after ingestion:
```sql
SELECT type, count(*) FROM iceberg.events.events GROUP BY type;
SELECT * FROM iceberg.events.events WHERE type = 'track' LIMIT 10;
```

When Trino executes a query it: looks up `metadata_location` in PostgreSQL -> reads the `metadata` files from MinIO -> reads the `parquet` data files from MinIO. \
Postgres catalog is only an entry point for Trino while the actual metadata and data lives in the bucket. \
OLake writes to both layers: it updates the pointer in PostgreSQL at each change and writes metadata + parquet files to MinIO. \
Similarly, when dlt commits a new snapshot, PyIceberg (which dlt uses under the hood) updates the `metadata_location` pointer in the `iceberg_tables`.
Both pipelines share the same two-layer write path.
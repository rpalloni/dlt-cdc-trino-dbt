CDC pipeline: PostgreSQL changes are captured in real time and written to Apache Iceberg tables on MinIO object storage.
events pipeline: 

Trino as query engine to read Iceberg tables.

## Architecture
```
PostgreSQL (WAL) --> OLake --> Iceberg / MinIO
```

| Component | Role |
|---|---|
| PostgreSQL 18 | Source database with logical replication enabled |
| OLake | CDC engine — reads WAL via replication slot, writes Iceberg |
| MinIO | S3-compatible object store hosting Iceberg data files |

OLake uses a JDBC catalog (backed by the same PostgreSQL instance) to track Iceberg table metadata.


## Run
```bash
# Start the full stack
make up

# Tear down (containers + volumes)
make destroy
```

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

OLake registers tables under the catalog name `olake_iceberg` (set in `iceberg.jdbc-catalog-name` in `iceberg.properties`).


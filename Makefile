# keep this startup order, olake last
COMPOSE = docker compose \
	-f docker/docker-compose-pg-cdc.yml \
	-f docker/docker-compose-storage.yml \
	-f docker/docker-compose-olake.yml \
	-f docker/docker-compose-trino.yml \
	--env-file docker/.env

network:
	docker network inspect data-network >/dev/null 2>&1 || docker network create data-network

up: network
	$(COMPOSE) up --build

events:
	cd loader && uv run events-engine.py

ingest:
	cd loader && uv run events-ingestion.py

transform:
	cd transformer && uv run dbt run

test:
	cd transformer && uv run dbt test
	
down: 
	$(COMPOSE) down

destroy: 
	$(COMPOSE) down --remove-orphans -v
	echo '{}' > docker/olake/config/state.json # clear Log Sequence Number (change position in the WAL)
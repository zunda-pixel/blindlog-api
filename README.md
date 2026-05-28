# Blindlog API Server

> [!WARNING]
> This API/service has not been released yet. Destructive changes can happen when they better align the schema and implementation with the intended design.

- https://api.blindlog.me/
- Documents https://api.blindlog.me/documents

## Development Policy

In the database design of this repository, an immutable data model is adopted as a general rule.

## Run on Local

- Postgres

```sh
container run --rm \
  --name blindlog-postgres \
  -e "POSTGRES_PASSWORD=test_password" \
  -e "POSTGRES_USER=test_user" \
  -e "POSTGRES_DB=test_database" \
  -p 5432:5432 \
  postgres:latest
```

- Valkey

```sh
container run --rm \
  --name blindlog-valkey \
  -p 6379:6379 \
  valkey/valkey:latest
```

- OpenTelemetry Collector

```sh
container run --rm \
  --name blindlog-otel-collector \
  -p 4317:4317 \
  -p 4318:4318 \
  -v "$PWD/Deploy/local/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml" \
  ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:latest
```

# Blindlog API Server

## Run on Local

- Postgres

```
container run -e "POSTGRES_PASSWORD=test_password" -e "POSTGRES_USER=test_user" -e "POSTGRES_DB=test_database" -p 5432:5432 postgres:latest
```

- Valkey

```
valkey-server
```

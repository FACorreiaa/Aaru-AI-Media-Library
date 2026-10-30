# aaru-server-v2

The Aaru API in Go: echo, pgx, sqlc, goose. A 1:1 port of `aaru-server`
(Swift/Hummingbird) on the same `openapi.yaml`, database and environment.
See [PORTING.md](PORTING.md) for the layout and conventions.

```bash
docker compose up -d && make test
```

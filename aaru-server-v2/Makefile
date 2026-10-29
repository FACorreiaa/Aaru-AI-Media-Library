# Aaru API (Go). Tests need Postgres: `docker compose up -d` here, or set POSTGRES_*.
.PHONY: generate api sqlc build test lint fmt run migrate

generate: api sqlc

api:
	./scripts/generate-api.sh

sqlc:
	go tool sqlc generate

build:
	go build -o bin/aaru ./cmd/aaru

test:
	go test ./...

lint:
	golangci-lint run ./...

fmt:
	go tool gofumpt -w .

run:
	go run ./cmd/aaru

migrate:
	go run ./cmd/aaru --db-migrate

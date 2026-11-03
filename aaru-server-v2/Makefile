# Aaru API (Go). Tests need Postgres: `docker compose up -d` here, or set POSTGRES_*.
# Tools (sqlc, oapi-codegen, gofumpt, staticcheck) are `go tool` dependencies in go.mod.

# gofumpt as golangci-lint runs it (.golangci.yml sets no module-path): with the module path unset,
# a dot-less import path such as aaru-go-api/... groups with the standard library. Plain
# `go tool gofumpt` reads the path from go.mod and would split those imports out of every file,
# which golangci-lint then rejects. The -modpath below matches nothing, so both agree.
GOFUMPT = go tool gofumpt -modpath=unset.invalid
.PHONY: generate api sqlc build test lint fmt run migrate check-fmt vet staticcheck test-race vuln check-all

generate: api sqlc

api:
	./scripts/generate-api.sh

sqlc:
	go tool sqlc generate

build:
	go build -o bin/aaru ./cmd/aaru

test:
	go test -race ./...

lint:
	golangci-lint run ./...

fmt:
	$(GOFUMPT) -w .

run:
	go run ./cmd/aaru

migrate:
	go run ./cmd/aaru --db-migrate

check-fmt: ## Format validation — list files gofumpt would change
	@bad=$$($(GOFUMPT) -l .); \
	if [ -n "$$bad" ]; then \
		echo "The following files need gofumpt (make fmt):"; echo "$$bad"; exit 1; \
	fi
	@echo "gofumpt: OK"

vet: ## Built-in static analysis
	go vet ./...

staticcheck: ## Advanced static analysis (a go tool dependency)
	go tool staticcheck ./...

test-race: ## Unit tests with race detection (×10)
	go test -race -count=10 ./...

vuln: ## Known vulnerabilities in reachable code (same pinned version as CI)
	go run golang.org/x/vuln/cmd/govulncheck@v1.9.0 ./...

check-all: check-fmt vet staticcheck test-race ## Run all checks (fmt, vet, staticcheck, tests)

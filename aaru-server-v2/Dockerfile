# Build context: this directory (`docker build -t aaru-server aaru-server-v2`).
FROM golang:1.27-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG AARU_RELEASE=""
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/aaru ./cmd/aaru

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/aaru /app/aaru
# The commit this image was built from, as the release on Sentry error reports.
ARG AARU_RELEASE=""
ENV AARU_RELEASE=$AARU_RELEASE
EXPOSE 8080
# Same entrypoint and flags as the Swift image, so the chart does not change:
# `--db-migrate` and `--anime-mappings` are one-shot modes.
ENTRYPOINT ["/app/aaru"]
CMD ["--http-host", "0.0.0.0", "--http-port", "8080"]

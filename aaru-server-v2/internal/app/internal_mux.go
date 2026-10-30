package app

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/metrics"
	"net/http"
	"net/http/pprof"
	"runtime"
)

// internalMux serves the internal port (METRICS_PORT): Prometheus at `/metrics`
// and, unless PPROF_ENABLED=false, Go's profiler at `/debug/pprof/`. The port is
// in neither the Service nor the Ingress, so only in-cluster scrapers (Alloy)
// reach it on the pod IP; profiles never leave the cluster otherwise.
//
// Flame graphs: `kubectl port-forward <pod> 9090` then
// `go tool pprof -http=:0 http://localhost:9090/debug/pprof/profile?seconds=30`,
// or Alloy's `pyroscope.scrape` for continuous profiles in Grafana.
func internalMux(cfg *config.App) *http.ServeMux {
	mux := http.NewServeMux()
	mux.Handle("GET /metrics", metrics.Handler())
	if !cfg.Pprof.Enabled {
		return mux
	}
	// Block and mutex profiles are empty unless sampled; both cost a little on every event.
	runtime.SetBlockProfileRate(cfg.Pprof.BlockRate)
	runtime.SetMutexProfileFraction(cfg.Pprof.MutexFraction)
	mux.HandleFunc("GET /debug/pprof/", pprof.Index)
	mux.HandleFunc("GET /debug/pprof/cmdline", pprof.Cmdline)
	mux.HandleFunc("GET /debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("GET /debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("POST /debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("GET /debug/pprof/trace", pprof.Trace)
	return mux
}

package metrics

import (
	"aaru-go-api/internal/safe"
	"context"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// Background workers (Go audit REL-004). Label values are worker names, queue names and a short
// result or step: a fixed set, never an id.

// Worker pass results.
const (
	PassOK    = "ok"
	PassError = "error"
	PassPanic = "panic"
)

var (
	workerPasses   *prometheus.CounterVec
	workerSuccess  *prometheus.GaugeVec
	refreshFailure *prometheus.CounterVec

	queueSourceMu sync.RWMutex
	queueSource   func(context.Context) ([]QueueStat, error)
)

func init() { registerWorkers() }

func registerWorkers() {
	workerPasses = counter("aaru_worker_passes_total",
		"Background worker passes (or job steps), by worker and result (ok, error, panic).", "worker", "result")
	workerSuccess = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "aaru_worker_last_success_timestamp_seconds",
		Help: "Unix time of each worker's last pass that ended without an error.",
	}, []string{"worker"})
	refreshFailure = counter("aaru_catalog_refresh_failures_total",
		"Catalog refresh lookups that failed, by step (episodes, genres, page_counts).", "step")
	Registry.MustRegister(workerSuccess, queueCollector{})
}

// WorkerPass records one pass of a worker: ok (and the last-success time), error, or panic. A pass
// cut short by shutdown is not recorded: callers skip it.
func WorkerPass(worker string, err error) {
	switch {
	case err == nil:
		workerPasses.WithLabelValues(worker, PassOK).Inc()
		workerSuccess.WithLabelValues(worker).Set(float64(time.Now().UnixNano()) / 1e9)
	case safe.IsPanic(err):
		workerPasses.WithLabelValues(worker, PassPanic).Inc()
	default:
		workerPasses.WithLabelValues(worker, PassError).Inc()
	}
}

// RefreshFailed counts one catalog refresh lookup the provider failed.
func RefreshFailed(step string) {
	refreshFailure.WithLabelValues(step).Inc()
}

// QueueStat is one leased queue's backlog.
type QueueStat struct {
	Queue string
	// Depth is jobs waiting to be claimed.
	Depth int64
	// OldestAge is how long the oldest waiting job has waited; zero when none waits.
	OldestAge time.Duration
}

// SetQueueSource sets what the queue gauges read at scrape time (the database). Setting it again
// replaces it; nil turns the gauges off.
func SetQueueSource(source func(context.Context) ([]QueueStat, error)) {
	queueSourceMu.Lock()
	defer queueSourceMu.Unlock()
	queueSource = source
}

var (
	queueDepthDesc = prometheus.NewDesc("aaru_queue_depth",
		"Jobs waiting to be claimed, by queue (import_jobs, agent_replies).", []string{"queue"}, nil)
	queueAgeDesc = prometheus.NewDesc("aaru_queue_oldest_age_seconds",
		"How long the oldest waiting job has waited, by queue.", []string{"queue"}, nil)
)

// queueCollector reads the queues on each scrape; a failed read leaves the gauges out of that scrape.
type queueCollector struct{}

func (queueCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- queueDepthDesc
	ch <- queueAgeDesc
}

func (queueCollector) Collect(ch chan<- prometheus.Metric) {
	queueSourceMu.RLock()
	source := queueSource
	queueSourceMu.RUnlock()
	if source == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	stats, err := source(ctx)
	if err != nil {
		return
	}
	for _, s := range stats {
		ch <- prometheus.MustNewConstMetric(queueDepthDesc, prometheus.GaugeValue, float64(s.Depth), s.Queue)
		ch <- prometheus.MustNewConstMetric(queueAgeDesc, prometheus.GaugeValue, s.OldestAge.Seconds(), s.Queue)
	}
}

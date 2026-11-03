package metrics

import (
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
)

// The Postgres pool (Go audit DB-002): one pool serves requests and every worker, so whether it
// runs out is the first thing to know before resizing it.

var (
	poolAcquiredDesc = prometheus.NewDesc("aaru_db_pool_acquired_connections",
		"Pool connections checked out now.", nil, nil)
	poolIdleDesc = prometheus.NewDesc("aaru_db_pool_idle_connections",
		"Pool connections open and idle now.", nil, nil)
	poolTotalDesc = prometheus.NewDesc("aaru_db_pool_total_connections",
		"Pool connections open now (acquired, idle and being opened).", nil, nil)
	poolMaxDesc = prometheus.NewDesc("aaru_db_pool_max_connections",
		"The pool's size (POSTGRES_POOL_SIZE).", nil, nil)
	poolAcquiresDesc = prometheus.NewDesc("aaru_db_pool_acquires_total",
		"Connections acquired from the pool.", nil, nil)
	poolEmptyAcquiresDesc = prometheus.NewDesc("aaru_db_pool_empty_acquires_total",
		"Acquires that had to wait because no connection was idle.", nil, nil)
	poolCanceledAcquiresDesc = prometheus.NewDesc("aaru_db_pool_canceled_acquires_total",
		"Acquires given up because their context ended while waiting.", nil, nil)
	poolAcquireSecondsDesc = prometheus.NewDesc("aaru_db_pool_acquire_duration_seconds_total",
		"Total time spent acquiring connections; divide by acquires for the mean wait.", nil, nil)
)

// poolCollector reads pgxpool.Stat on each scrape.
type poolCollector struct {
	stat func() *pgxpool.Stat
}

func (poolCollector) Describe(ch chan<- *prometheus.Desc) {
	for _, d := range []*prometheus.Desc{
		poolAcquiredDesc, poolIdleDesc, poolTotalDesc, poolMaxDesc, poolAcquiresDesc, poolEmptyAcquiresDesc,
		poolCanceledAcquiresDesc, poolAcquireSecondsDesc,
	} {
		ch <- d
	}
}

func (c poolCollector) Collect(ch chan<- prometheus.Metric) {
	s := c.stat()
	gauge := func(d *prometheus.Desc, v float64) {
		ch <- prometheus.MustNewConstMetric(d, prometheus.GaugeValue, v)
	}
	count := func(d *prometheus.Desc, v float64) {
		ch <- prometheus.MustNewConstMetric(d, prometheus.CounterValue, v)
	}
	gauge(poolAcquiredDesc, float64(s.AcquiredConns()))
	gauge(poolIdleDesc, float64(s.IdleConns()))
	gauge(poolTotalDesc, float64(s.TotalConns()))
	gauge(poolMaxDesc, float64(s.MaxConns()))
	count(poolAcquiresDesc, float64(s.AcquireCount()))
	count(poolEmptyAcquiresDesc, float64(s.EmptyAcquireCount()))
	count(poolCanceledAcquiresDesc, float64(s.CanceledAcquireCount()))
	count(poolAcquireSecondsDesc, s.AcquireDuration().Seconds())
}

// RegisterPool exports the pool's statistics on `/metrics`.
func RegisterPool(pool *pgxpool.Pool) error {
	if err := Registry.Register(poolCollector{stat: pool.Stat}); err != nil {
		return fmt.Errorf("register pool metrics: %w", err)
	}
	return nil
}

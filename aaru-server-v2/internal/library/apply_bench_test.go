package library

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// statementCounter counts the statements a connection sends.
type statementCounter struct {
	n atomic.Int64
}

func (c *statementCounter) TraceQueryStart(ctx context.Context, _ *pgx.Conn, _ pgx.TraceQueryStartData) context.Context {
	c.n.Add(1)
	return ctx
}

func (c *statementCounter) TraceQueryEnd(context.Context, *pgx.Conn, pgx.TraceQueryEndData) {}

// BenchmarkImportApply is one import approval's write (PERF-003): n new library items in one
// transaction, one journaled action. "statements/op" is the round trips it makes.
func BenchmarkImportApply(b *testing.B) {
	for _, n := range []int{500, 2000} {
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			ctx := context.Background()
			base := testdb.New(b)
			counter := &statementCounter{}
			cfg := base.Config().Copy()
			cfg.ConnConfig.Tracer = counter
			pool, err := pgxpool.NewWithConfig(ctx, cfg)
			if err != nil {
				b.Fatal(err)
			}
			defer pool.Close()
			store := NewStore(pool)
			titles := make([]uuid.UUID, n)
			for i := range titles {
				titles[i] = uuid.New()
				if _, err := pool.Exec(ctx, `INSERT INTO titles (id, type, title) VALUES ($1, 'movie', $2)`,
					titles[i], fmt.Sprintf("title %d", i)); err != nil {
					b.Fatal(err)
				}
			}
			counter.n.Store(0)
			b.ReportAllocs()
			runs := 0
			for b.Loop() {
				user := uuid.New()
				if _, err := pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, user); err != nil {
					b.Fatal(err)
				}
				ops := make([]Op, n)
				for i, title := range titles {
					ops[i] = InsertItem(ItemSnapshot{
						ID: uuid.New(), TitleID: title, AddedAt: time.Now(),
						Fields: ItemFields{Status: core.StatusFinished},
					})
				}
				if _, err := store.Apply(ctx, Batch(ops...), user, UserCaller, "import", "bench"); err != nil {
					b.Fatal(err)
				}
				runs++
			}
			b.ReportMetric(float64(counter.n.Load())/float64(runs), "statements/op")
		})
	}
}

package thumbnail

import (
	"context"
	"gallery/common/misc"
	"log"
	"sync"
	"time"

	"github.com/XGFan/go-utils"
)

const (
	defaultPosterDedupTTL     = 10 * time.Second
	defaultPosterConcurrency  = 1
	defaultPosterQueueCapcity = 64
)

type PosterGenerator interface {
	Generate(ctx context.Context, source string) error
}

type PosterTask struct {
	Source string
}

type PosterQueueOptions struct {
	Concurrency   int
	DedupTTL      time.Duration
	QueueCapacity int
}

type posterDedupCache interface {
	Filter(string) bool
}

type PosterQueue struct {
	generator   PosterGenerator
	queue       misc.UnboundedChan[PosterTask]
	concurrency int
	cache       posterDedupCache
	cacheMu     sync.Mutex
}

func NewPosterQueue(generator PosterGenerator, options PosterQueueOptions) *PosterQueue {
	ttl := options.DedupTTL
	if ttl <= 0 {
		ttl = defaultPosterDedupTTL
	}

	concurrency := options.Concurrency
	if concurrency <= 0 {
		concurrency = defaultPosterConcurrency
	}

	queueCapacity := options.QueueCapacity
	if queueCapacity <= 0 {
		queueCapacity = defaultPosterQueueCapcity
	}

	return &PosterQueue{
		generator:   generator,
		queue:       misc.NewUnboundedChan[PosterTask](queueCapacity),
		concurrency: concurrency,
		cache:       utils.NewTTlCache[string, string](ttl),
	}
}

func (pq *PosterQueue) Enqueue(source string) {
	if source == "" {
		return
	}

	task := PosterTask{Source: source}
	select {
	case pq.queue.In <- task:
	default:
		go func() {
			pq.queue.In <- task
		}()
	}
}

func (pq *PosterQueue) Run(ctx context.Context) {
	for i := 0; i < pq.concurrency; i++ {
		go pq.runWorker(ctx)
	}
}

func (pq *PosterQueue) runWorker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case task, ok := <-pq.queue.Out:
			if !ok {
				return
			}
			if !pq.allow(task.Source) {
				continue
			}
			if pq.generator == nil {
				continue
			}
			if err := pq.generator.Generate(ctx, task.Source); err != nil {
				log.Printf("poster generate failed: %s, err: %v", task.Source, err)
			}
		}
	}
}

func (pq *PosterQueue) allow(source string) bool {
	pq.cacheMu.Lock()
	defer pq.cacheMu.Unlock()
	return pq.cache.Filter(source)
}

package thumbnail

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

type posterGeneratorFunc func(ctx context.Context, source string) error

func (fn posterGeneratorFunc) Generate(ctx context.Context, source string) error {
	return fn(ctx, source)
}

func TestPosterQueueDedup(t *testing.T) {
	var count int32
	generator := posterGeneratorFunc(func(ctx context.Context, source string) error {
		atomic.AddInt32(&count, 1)
		return nil
	})

	queue := NewPosterQueue(generator, PosterQueueOptions{
		Concurrency:   1,
		DedupTTL:      200 * time.Millisecond,
		QueueCapacity: 1,
	})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	queue.Run(ctx)

	for i := 0; i < 5; i++ {
		queue.Enqueue("videos/clip.mp4")
	}

	waitForPosterCount(t, &count, 1, time.Second)
	time.Sleep(100 * time.Millisecond)

	if got := atomic.LoadInt32(&count); got != 1 {
		t.Fatalf("expected dedup to run once, got %d", got)
	}
}

func TestPosterQueueNonBlocking(t *testing.T) {
	block := make(chan struct{})
	generator := posterGeneratorFunc(func(ctx context.Context, source string) error {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-block:
			return nil
		}
	})

	queue := NewPosterQueue(generator, PosterQueueOptions{
		Concurrency:   1,
		DedupTTL:      time.Second,
		QueueCapacity: 1,
	})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	queue.Run(ctx)

	done := make(chan struct{})
	go func() {
		for i := 0; i < 1000; i++ {
			queue.Enqueue("videos/clip.mp4")
		}
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(200 * time.Millisecond):
		t.Fatal("enqueue should be non-blocking")
	}

	close(block)
}

func waitForPosterCount(t *testing.T, count *int32, want int32, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for {
		if atomic.LoadInt32(count) >= want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("timeout waiting for poster generation, want %d", want)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

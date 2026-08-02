// Package ratelimit implements the two limiters the gateway needs:
//
//   - Limiter: a per-key (client IP) token bucket used to police inbound
//     requests. Exhaustion maps to JSON-RPC error -32001.
//   - Interval: a serializing minimum-spacing limiter used for polite outbound
//     calls to shared public APIs (CoinGecko at 1 request/second).
package ratelimit

import (
	"context"
	"sync"
	"time"

	"ktwallet/gateway/internal/clock"
)

type bucket struct {
	tokens float64
	last   time.Time
}

// Limiter is a token-bucket rate limiter keyed by an arbitrary string
// (typically the client IP). Refill is computed lazily from the injected
// clock, so tests can drive it deterministically.
type Limiter struct {
	clk        clock.Clock
	rate       float64 // tokens per second
	burst      float64
	maxBuckets int

	mu      sync.Mutex
	buckets map[string]*bucket
}

const (
	defaultMaxBuckets = 65536
	overflowBucketKey = "\x00overflow"
)

// New returns a Limiter allowing `rate` requests per second with a burst
// capacity of `burst` per key.
func New(clk clock.Clock, rate float64, burst float64) *Limiter {
	return newLimiter(clk, rate, burst, defaultMaxBuckets)
}

func newLimiter(clk clock.Clock, rate float64, burst float64, maxBuckets int) *Limiter {
	if rate <= 0 {
		rate = 1
	}
	if burst < 1 {
		burst = 1
	}
	if maxBuckets < 1 {
		maxBuckets = 1
	}
	return &Limiter{
		clk:        clk,
		rate:       rate,
		burst:      burst,
		maxBuckets: maxBuckets,
		buckets:    make(map[string]*bucket),
	}
}

// Allow reports whether one request for key fits in the budget, consuming a
// token when it does.
func (l *Limiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.clk.Now()

	// Bound memory: first drop buckets that have fully refilled (they are
	// indistinguishable from fresh ones). If a high-cardinality IP flood keeps
	// every bucket active, new keys share one conservative overflow bucket
	// instead of growing memory without limit.
	regularCapacity := l.maxBuckets - 1 // reserve one slot for overflow
	if _, exists := l.buckets[key]; !exists && len(l.buckets) >= regularCapacity {
		for k, b := range l.buckets {
			if k != overflowBucketKey && now.Sub(b.last).Seconds()*l.rate >= l.burst {
				delete(l.buckets, k)
			}
		}
		if len(l.buckets) >= regularCapacity {
			key = overflowBucketKey
		}
	}

	b, ok := l.buckets[key]
	if !ok {
		b = &bucket{tokens: l.burst, last: now}
		l.buckets[key] = b
	} else if elapsed := now.Sub(b.last).Seconds(); elapsed > 0 {
		b.tokens += elapsed * l.rate
		if b.tokens > l.burst {
			b.tokens = l.burst
		}
		b.last = now
	}
	if b.tokens >= 1 {
		b.tokens--
		return true
	}
	return false
}

// Interval enforces a minimum spacing between successive calls and serializes
// callers: concurrent Wait calls are released one at a time, each at least
// `interval` after the previous release. It uses real time on purpose — it
// exists to be polite to real upstream services.
type Interval struct {
	mu       sync.Mutex
	interval time.Duration
	last     time.Time
}

// NewInterval returns an Interval limiter with the given minimum spacing.
func NewInterval(interval time.Duration) *Interval {
	return &Interval{interval: interval}
}

// Wait blocks until the caller may proceed, or until ctx is done.
func (i *Interval) Wait(ctx context.Context) error {
	i.mu.Lock()
	defer i.mu.Unlock()
	if !i.last.IsZero() {
		if wait := i.interval - time.Since(i.last); wait > 0 {
			t := time.NewTimer(wait)
			defer t.Stop()
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-t.C:
			}
		}
	}
	i.last = time.Now()
	return nil
}

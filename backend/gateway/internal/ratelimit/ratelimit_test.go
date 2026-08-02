package ratelimit

import (
	"context"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

func TestLimiterBurstThenExhaustion(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	l := New(clk, 1, 3)
	for i := 0; i < 3; i++ {
		if !l.Allow("ip1") {
			t.Fatalf("request %d within burst should pass", i+1)
		}
	}
	if l.Allow("ip1") {
		t.Fatal("4th request with burst 3 and no elapsed time should be rejected")
	}
}

func TestLimiterRefill(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	l := New(clk, 2, 2) // 2 rps
	if !l.Allow("k") || !l.Allow("k") {
		t.Fatal("burst should pass")
	}
	if l.Allow("k") {
		t.Fatal("bucket should be empty")
	}
	clk.Advance(500 * time.Millisecond) // refills exactly one token at 2 rps
	if !l.Allow("k") {
		t.Fatal("expected one token after refill")
	}
	if l.Allow("k") {
		t.Fatal("only one token should have refilled")
	}
}

func TestLimiterKeysAreIsolated(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	l := New(clk, 1, 1)
	if !l.Allow("a") {
		t.Fatal("first key should pass")
	}
	if l.Allow("a") {
		t.Fatal("first key should now be exhausted")
	}
	if !l.Allow("b") {
		t.Fatal("second key must not be affected by the first key's usage")
	}
}

func TestLimiterBoundsHighCardinalityClients(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	l := newLimiter(clk, 1, 1, 4)
	for _, key := range []string{"a", "b", "c", "d"} {
		if !l.Allow(key) {
			t.Fatalf("first request for %q should pass", key)
		}
	}
	if len(l.buckets) != 4 {
		t.Fatalf("bucket table grew to %d, want hard cap 4", len(l.buckets))
	}
	if l.Allow("e") {
		t.Fatal("new high-cardinality clients must share the exhausted overflow bucket")
	}
	if len(l.buckets) != 4 {
		t.Fatalf("overflow traffic grew bucket table to %d", len(l.buckets))
	}
}

func TestLimiterReclaimsFullyRefilledBucketsBeforeOverflow(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	l := newLimiter(clk, 1, 1, 3)
	if !l.Allow("a") || !l.Allow("b") {
		t.Fatal("initial keys should pass")
	}
	clk.Advance(2 * time.Second)
	if !l.Allow("c") {
		t.Fatal("a new key should use reclaimed capacity")
	}
	if _, exists := l.buckets[overflowBucketKey]; exists {
		t.Fatal("reclaimable idle buckets must not force overflow limiting")
	}
	if len(l.buckets) != 1 {
		t.Fatalf("expected only the new live bucket, got %d", len(l.buckets))
	}
}

func TestIntervalSpacesCalls(t *testing.T) {
	iv := NewInterval(120 * time.Millisecond)
	ctx := context.Background()

	if err := iv.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	if err := iv.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	if elapsed := time.Since(start); elapsed < 100*time.Millisecond {
		t.Fatalf("second Wait returned after %v; want >= ~120ms spacing", elapsed)
	}
}

func TestIntervalRespectsContext(t *testing.T) {
	iv := NewInterval(10 * time.Second)
	if err := iv.Wait(context.Background()); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	if err := iv.Wait(ctx); err == nil {
		t.Fatal("expected context deadline error while waiting for a 10s interval")
	}
}

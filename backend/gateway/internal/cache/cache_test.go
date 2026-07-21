package cache

import (
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

func TestCacheHitWithinTTL(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	c := New(clk, 30*time.Second)
	c.Set("k", 42)

	v, ok := c.Get("k")
	if !ok || v.(int) != 42 {
		t.Fatalf("expected hit with 42, got %v %v", v, ok)
	}
	clk.Advance(29 * time.Second)
	if _, ok := c.Get("k"); !ok {
		t.Fatal("expected hit at 29s for a 30s TTL")
	}
}

func TestCacheExpiry(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	c := New(clk, 30*time.Second)
	c.Set("k", "v")
	clk.Advance(31 * time.Second)
	if _, ok := c.Get("k"); ok {
		t.Fatal("expected miss after TTL")
	}
	if c.Len() != 0 {
		t.Fatalf("expired entry should be evicted on read, len=%d", c.Len())
	}
}

func TestCacheMissUnknownKey(t *testing.T) {
	c := New(clock.NewFake(time.Unix(0, 0)), time.Second)
	if _, ok := c.Get("nope"); ok {
		t.Fatal("expected miss for unknown key")
	}
}

func TestCacheOverwrite(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	c := New(clk, 10*time.Second)
	c.Set("k", 1)
	clk.Advance(9 * time.Second)
	c.Set("k", 2) // refreshes value and TTL
	clk.Advance(9 * time.Second)
	v, ok := c.Get("k")
	if !ok || v.(int) != 2 {
		t.Fatalf("expected refreshed value 2, got %v %v", v, ok)
	}
}

package cache

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

type fakeStore struct {
	mu      sync.Mutex
	values  map[string][]byte
	lastKey string
	err     error
}

func newFakeStore() *fakeStore {
	return &fakeStore{values: make(map[string][]byte)}
}

func (s *fakeStore) Get(_ context.Context, key string) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastKey = key
	if s.err != nil {
		return nil, s.err
	}
	value, ok := s.values[key]
	if !ok {
		return nil, ErrNotFound
	}
	return append([]byte(nil), value...), nil
}

func (s *fakeStore) Set(_ context.Context, key string, value []byte, _ time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastKey = key
	if s.err != nil {
		return s.err
	}
	s.values[key] = append([]byte(nil), value...)
	return nil
}

type sharedValue struct {
	Amount string `json:"amount"`
}

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

func TestSharedCacheCrossInstanceHitUsesHashedKey(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	store := newFakeStore()
	codec := JSONPointerCodec[sharedValue]()
	first := NewShared(clk, 30*time.Second, store, "balances", codec)
	second := NewShared(clk, 30*time.Second, store, "balances", codec)
	const rawKey = "eth-mainnet|0x1234567890abcdef|tokens"

	first.Set(rawKey, &sharedValue{Amount: "42"})
	if strings.Contains(store.lastKey, "0x1234567890abcdef") ||
		strings.Contains(store.lastKey, "eth-mainnet") {
		t.Fatalf("shared key leaked raw cache material: %q", store.lastKey)
	}
	value, ok := second.Get(rawKey)
	if !ok || value.(*sharedValue).Amount != "42" {
		t.Fatalf("expected cross-instance hit, got %#v, %v", value, ok)
	}
	stats := second.Stats()
	if stats.Hits != 1 || stats.Misses != 0 || stats.Errors != 0 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
}

func TestSharedCacheExpiryAndFailureFallBackToMiss(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	store := newFakeStore()
	codec := JSONPointerCodec[sharedValue]()
	first := NewShared(clk, time.Second, store, "history", codec)
	second := NewShared(clk, time.Second, store, "history", codec)
	first.Set("wallet", &sharedValue{Amount: "1"})
	clk.Advance(2 * time.Second)
	if _, ok := second.Get("wallet"); ok {
		t.Fatal("expired shared value must not be served")
	}
	if second.Stats().Misses != 1 {
		t.Fatalf("expired read must count as a miss: %+v", second.Stats())
	}

	store.err = errors.New("redis unavailable")
	third := NewShared(clk, time.Second, store, "history", codec)
	if _, ok := third.Get("other"); ok {
		t.Fatal("shared-store failure must fall back to a miss")
	}
	if third.Stats().Errors != 1 {
		t.Fatalf("shared failure must be observable: %+v", third.Stats())
	}
}

func TestOversizedSharedValueStaysLocalAndIsNotPublished(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	store := newFakeStore()
	cache := NewShared(
		clk,
		time.Minute,
		store,
		"history",
		JSONPointerCodec[sharedValue](),
	)
	cache.Set("wallet", &sharedValue{Amount: strings.Repeat("9", maxSharedValueBytes)})

	if len(store.values) != 0 {
		t.Fatal("oversized shared value must not be published")
	}
	if cache.Stats().Errors != 1 {
		t.Fatalf("oversized value must be observable: %+v", cache.Stats())
	}
	if value, ok := cache.Get("wallet"); !ok || value.(*sharedValue).Amount == "" {
		t.Fatal("shared serialization guard must not discard the safe local value")
	}
}

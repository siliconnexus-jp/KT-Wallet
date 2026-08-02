package handlers_test

import (
	"context"
	"strings"
	"sync"
	"testing"
	"time"

	"ktwallet/gateway/internal/cache"
	"ktwallet/gateway/internal/handlers"
)

type sharedTestStore struct {
	mu      sync.Mutex
	values  map[string][]byte
	lastKey string
}

func newSharedTestStore() *sharedTestStore {
	return &sharedTestStore{values: make(map[string][]byte)}
}

func (s *sharedTestStore) Get(_ context.Context, key string) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastKey = key
	value, ok := s.values[key]
	if !ok {
		return nil, cache.ErrNotFound
	}
	return append([]byte(nil), value...), nil
}

func (s *sharedTestStore) Set(_ context.Context, key string, value []byte, _ time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastKey = key
	s.values[key] = append([]byte(nil), value...)
	return nil
}

func TestSharedCacheServesSecondGatewayWithoutLeakingAddressInKey(t *testing.T) {
	store := newSharedTestStore()
	firstNode := newRPCFake(t)
	firstNode.result("eth_getBalance", "0x64")
	secondNode := newRPCFake(t)
	secondNode.result("eth_getBalance", "0xc8")

	first := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{firstNode.srv.URL}
		cfg.SharedCache = store
	})
	second := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{secondNode.srv.URL}
		cfg.SharedCache = store
	})

	gotFirst := result(t, first.rpc("kt_getBalances", balancesParams("eth", evmSelf, "")))
	if gotFirst["native"].(map[string]any)["raw"] != "100" {
		t.Fatalf("unexpected first balance: %#v", gotFirst)
	}
	gotSecond := result(t, second.rpc("kt_getBalances", balancesParams("eth", evmSelf, "")))
	if gotSecond["native"].(map[string]any)["raw"] != "100" {
		t.Fatalf("second instance did not use shared value: %#v", gotSecond)
	}
	if secondNode.count("eth_getBalance") != 0 {
		t.Fatalf("shared hit must avoid second upstream, calls=%d", secondNode.count("eth_getBalance"))
	}
	if strings.Contains(store.lastKey, evmSelf) || strings.Contains(store.lastKey, "eth-mainnet") {
		t.Fatalf("shared cache key leaked request identity: %q", store.lastKey)
	}
	metrics := second.gw.Metrics()
	for _, want := range []string{
		`kt_gateway_shared_cache_enabled{cache="balances"} 1`,
		`kt_gateway_shared_cache_operations_total{cache="balances",outcome="hit"} 1`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics missing %q:\n%s", want, metrics)
		}
	}
}

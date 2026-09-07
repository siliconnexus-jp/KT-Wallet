package handlers

import (
	"context"
	"fmt"
	"ktwallet/gateway/internal/clock"
	"sync"
	"testing"
	"time"
)

func TestBroadcastGuardCapacityPreservesLiveClaims(t *testing.T) {
	clk := clock.NewFake(time.Unix(1, 0))
	g := newBroadcastGuard(clk, nil)
	ctx := context.Background()
	for i := 0; i < maxBroadcastRecords; i++ {
		_, owner, err := g.begin(ctx, fmt.Sprint(i))
		if err != nil || !owner {
			t.Fatalf("claim %d: %v", i, err)
		}
	}
	if _, owner, err := g.begin(ctx, "overflow"); owner || err == nil {
		t.Fatal("over capacity accepted")
	}
	if _, owner, err := g.begin(ctx, "0"); owner || err != nil {
		t.Fatal("live replay not preserved")
	}
	if len(g.records) != maxBroadcastRecords || len(g.expiries) != maxBroadcastRecords {
		t.Fatal("unbounded storage")
	}
	if err := g.complete(ctx, "0", broadcastRecord{State: broadcastAccepted, TxHash: "known"}); err != nil {
		t.Fatal(err)
	}
	if len(g.expiries) != maxBroadcastRecords {
		t.Fatal("completion grows expiry index")
	}
	if r, owner, err := g.begin(ctx, "0"); owner || err != nil || r.TxHash != "known" {
		t.Fatal("terminal replay lost")
	}
	clk.Advance(broadcastGuardTTL)
	if _, owner, err := g.begin(ctx, "fresh"); !owner || err != nil {
		t.Fatal("expired entries prevent new work")
	}
	if len(g.records) != maxBroadcastRecords-broadcastExpirySweepBudget+1 {
		t.Fatal("expiry cleanup is not bounded")
	}
	if err := g.complete(ctx, "never-reserved", broadcastRecord{State: broadcastAccepted, TxHash: "x"}); err == nil {
		t.Fatal("unreserved completion allocated a record")
	}
}

func TestBroadcastGuardConcurrentCapacityWithSharedStore(t *testing.T) {
	g := newBroadcastGuard(clock.NewFake(time.Unix(1, 0)), &capacitySharedStore{values: make(map[string][]byte)})
	ctx := context.Background()
	for i := 0; i < maxBroadcastRecords-3; i++ {
		_, _, err := g.begin(ctx, fmt.Sprint(i))
		if err != nil {
			t.Fatal(err)
		}
	}
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, owner, err := g.begin(ctx, fmt.Sprintf("race-%d", i))
			if owner && err != nil {
				t.Error(err)
			}
		}(i)
	}
	wg.Wait()
	if len(g.records) != maxBroadcastRecords || len(g.expiries) != maxBroadcastRecords {
		t.Fatal("concurrent/shared requests bypass capacity")
	}
}

type capacitySharedStore struct {
	sync.Mutex
	values map[string][]byte
}

func (s *capacitySharedStore) Get(_ context.Context, key string) ([]byte, error) {
	s.Lock()
	defer s.Unlock()
	value, ok := s.values[key]
	if !ok {
		return nil, fmt.Errorf("missing test key")
	}
	return append([]byte(nil), value...), nil
}
func (s *capacitySharedStore) Set(_ context.Context, key string, value []byte, _ time.Duration) error {
	s.Lock()
	defer s.Unlock()
	s.values[key] = append([]byte(nil), value...)
	return nil
}
func (s *capacitySharedStore) SetNX(_ context.Context, key string, value []byte, _ time.Duration) (bool, error) {
	s.Lock()
	defer s.Unlock()
	if _, ok := s.values[key]; ok {
		return false, nil
	}
	s.values[key] = append([]byte(nil), value...)
	return true, nil
}

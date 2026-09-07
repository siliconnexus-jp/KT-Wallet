package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
	"ktwallet/gateway/internal/rpc"
)

func assertGuardBounded(t *testing.T, g *broadcastGuard) {
	t.Helper()
	if len(g.records) > maxBroadcastRecords || len(g.records) != len(g.expiries) || g.evictable.Len() > len(g.records) {
		t.Fatalf("unbounded/stale indexes: records=%d expiry=%d eviction=%d", len(g.records), len(g.expiries), g.evictable.Len())
	}
}

func TestBroadcastRejectedFloodCannotDisplaceUncertainOrAcceptedClaims(t *testing.T) {
	g := newBroadcastGuard(clock.NewFake(time.Unix(1, 0)), nil)
	ctx := context.Background()
	for _, state := range []string{broadcastAccepted, broadcastUnknown, broadcastPending} {
		g.begin(ctx, state)
		if state == broadcastAccepted {
			g.complete(ctx, state, broadcastRecord{State: state, TxHash: "accepted"})
		}
		if state == broadcastUnknown {
			g.complete(ctx, state, broadcastRecord{State: state, Error: rpc.Errorf(rpc.CodeSubmissionUnknown, "unknown")})
		}
	}
	for i := 0; i < maxBroadcastRecords*2; i++ {
		key := fmt.Sprint(i)
		if _, owner, err := g.begin(ctx, key); !owner || err != nil {
			t.Fatalf("claim %d: %v", i, err)
		}
		if err := g.complete(ctx, key, broadcastRecord{State: broadcastRejected, Error: rpc.Errorf(rpc.CodeUpstream, "rejected")}); err != nil {
			t.Fatal(err)
		}
		assertGuardBounded(t, g)
	}
	for _, state := range []string{broadcastAccepted, broadcastUnknown, broadcastPending} {
		if r, owner, err := g.begin(ctx, state); owner || err != nil || r.State != state {
			t.Fatalf("lost pinned %s", state)
		}
	}
	if _, owner, err := g.begin(ctx, "legitimate-new-transaction"); !owner || err != nil {
		t.Fatal("rejections exhausted new-work capacity")
	}
}

func TestBroadcastSharedResultsDoNotImposeDailyLocalQuota(t *testing.T) {
	store := &capacitySharedStore{values: make(map[string][]byte)}
	g := newBroadcastGuard(clock.NewFake(time.Unix(1, 0)), store)
	ctx := context.Background()
	for i := 0; i < maxBroadcastRecords*2; i++ {
		key := fmt.Sprint(i)
		if _, owner, err := g.begin(ctx, key); !owner || err != nil {
			t.Fatalf("claim %d: %v", i, err)
		}
		if err := g.complete(ctx, key, broadcastRecord{State: broadcastAccepted, TxHash: key}); err != nil {
			t.Fatal(err)
		}
		assertGuardBounded(t, g)
	}
	if _, exists := g.records["0"]; exists {
		t.Fatal("test did not exercise eviction")
	}
	for i := 0; i < maxBroadcastRecords*2; i++ {
		key := fmt.Sprint(i)
		if r, owner, err := g.begin(ctx, key); owner || err != nil || r.TxHash != key {
			t.Fatalf("evicted shared result resubmitted: %s", key)
		}
		assertGuardBounded(t, g)
	}
}

func TestBroadcastFullPinnedCacheStillReadsSharedReplay(t *testing.T) {
	store := &capacitySharedStore{values: make(map[string][]byte)}
	g := newBroadcastGuard(clock.NewFake(time.Unix(1, 0)), store)
	ctx := context.Background()
	for i := 0; i < maxBroadcastRecords; i++ {
		g.begin(ctx, fmt.Sprint(i))
	}
	raw, _ := json.Marshal(broadcastRecord{State: broadcastAccepted, TxHash: "peer-result"})
	store.Set(ctx, "peer", raw, broadcastGuardTTL)
	if r, owner, err := g.begin(ctx, "peer"); owner || err != nil || r.TxHash != "peer-result" {
		t.Fatal("full local cache hid a peer's result")
	}
	assertGuardBounded(t, g)
}

func TestBroadcastConcurrentCompletionAndEviction(t *testing.T) {
	store := &capacitySharedStore{values: make(map[string][]byte)}
	g := newBroadcastGuard(clock.NewFake(time.Unix(1, 0)), store)
	ctx := context.Background()
	var wg sync.WaitGroup
	for worker := 0; worker < 16; worker++ {
		wg.Add(1)
		go func(worker int) {
			defer wg.Done()
			for i := 0; i < 512; i++ {
				key := fmt.Sprintf("%d/%d", worker, i)
				if _, owner, err := g.begin(ctx, key); !owner || err != nil {
					t.Errorf("claim %s: %v", key, err)
					return
				}
				if err := g.complete(ctx, key, broadcastRecord{State: broadcastUnknown, Error: rpc.Errorf(rpc.CodeSubmissionUnknown, "unknown")}); err != nil {
					t.Error(err)
					return
				}
				if r, owner, err := g.begin(ctx, key); owner || err != nil || r.State != broadcastUnknown {
					t.Errorf("lost unknown outcome: %s", key)
					return
				}
			}
		}(worker)
	}
	wg.Wait()
	if r, owner, err := g.begin(ctx, "0/0"); owner || err != nil || r.State != broadcastUnknown {
		t.Fatal("evicted unknown outcome allowed a retry")
	}
	assertGuardBounded(t, g)
}

func TestBroadcastPeerPendingSnapshotRefreshesAfterCompletion(t *testing.T) {
	store := &capacitySharedStore{values: make(map[string][]byte)}
	clk := clock.NewFake(time.Unix(1, 0))
	first, second := newBroadcastGuard(clk, store), newBroadcastGuard(clk, store)
	ctx := context.Background()
	first.begin(ctx, "tx")
	if r, owner, err := second.begin(ctx, "tx"); owner || err != nil || r.State != broadcastPending {
		t.Fatal("expected peer pending")
	}
	first.complete(ctx, "tx", broadcastRecord{State: broadcastAccepted, TxHash: "done"})
	if r, owner, err := second.begin(ctx, "tx"); owner || err != nil || r.TxHash != "done" {
		t.Fatal("stale pending snapshot hid completion")
	}
}

type failingBroadcastStore struct {
	*capacitySharedStore
	failClaim, failPersist bool
}

func (s *failingBroadcastStore) SetNX(ctx context.Context, k string, v []byte, ttl time.Duration) (bool, error) {
	if s.failClaim {
		return false, fmt.Errorf("store offline")
	}
	return s.capacitySharedStore.SetNX(ctx, k, v, ttl)
}
func (s *failingBroadcastStore) Set(ctx context.Context, k string, v []byte, ttl time.Duration) error {
	if s.failPersist {
		return fmt.Errorf("store offline")
	}
	return s.capacitySharedStore.Set(ctx, k, v, ttl)
}

func TestBroadcastPreSubmissionStorageFailureDoesNotPoisonCapacity(t *testing.T) {
	store := &failingBroadcastStore{capacitySharedStore: &capacitySharedStore{values: make(map[string][]byte)}, failClaim: true}
	g := newBroadcastGuard(clock.NewFake(time.Unix(1, 0)), store)
	ctx := context.Background()
	for i := 0; i < maxBroadcastRecords+1; i++ {
		if _, owner, err := g.begin(ctx, fmt.Sprint(i)); owner || err == nil {
			t.Fatal("storage outage allowed broadcast")
		}
	}
	if len(g.records) != 0 || len(g.expiries) != 0 {
		t.Fatal("unsubmitted claims leaked")
	}
	store.failClaim = false
	if _, owner, err := g.begin(ctx, "0"); !owner || err != nil {
		t.Fatal("recovered store remained blocked")
	}
}

func TestBroadcastFailedPersistenceRemainsPinnedThroughEviction(t *testing.T) {
	store := &failingBroadcastStore{capacitySharedStore: &capacitySharedStore{values: make(map[string][]byte)}}
	g := newBroadcastGuard(clock.NewFake(time.Unix(1, 0)), store)
	ctx := context.Background()
	g.begin(ctx, "failed-persist")
	store.failPersist = true
	if g.complete(ctx, "failed-persist", broadcastRecord{State: broadcastAccepted, TxHash: "accepted"}) == nil {
		t.Fatal("expected failed persistence")
	}
	store.failPersist = false
	for i := 0; i < maxBroadcastRecords+10; i++ {
		key := fmt.Sprint(i)
		g.begin(ctx, key)
		g.complete(ctx, key, broadcastRecord{State: broadcastAccepted, TxHash: key})
	}
	if r, owner, err := g.begin(ctx, "failed-persist"); owner || err != nil || r.TxHash != "accepted" {
		t.Fatal("evicted unpersisted accepted transaction")
	}
	if g.records["failed-persist"].evictable != nil {
		t.Fatal("unpersisted result marked evictable")
	}
	assertGuardBounded(t, g)
}

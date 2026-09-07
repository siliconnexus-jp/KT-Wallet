package handlers

import (
	"container/heap"
	"container/list"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"ktwallet/gateway/internal/cache"
	"ktwallet/gateway/internal/clock"
	"ktwallet/gateway/internal/rpc"
)

// A signed transaction is immutable: replaying the exact bytes cannot create
// a different payment, but it can still fan out an irreversible write to more
// than one RPC provider. Keep a claim/result for long enough that browser,
// CDN, reverse-proxy and impatient-client replays converge on one outcome.
const broadcastGuardTTL = 24 * time.Hour

// Bound local memory, not daily throughput. Only records durably retained in
// the shared store, or explicit node rejections, may leave the local cache.
const maxBroadcastRecords = 4096
const broadcastExpirySweepBudget = 64

type broadcastExpiry struct {
	key   string
	at    time.Time
	index int
}
type broadcastExpiryHeap []*broadcastExpiry

func (h broadcastExpiryHeap) Len() int           { return len(h) }
func (h broadcastExpiryHeap) Less(i, j int) bool { return h[i].at.Before(h[j].at) }
func (h broadcastExpiryHeap) Swap(i, j int) {
	h[i], h[j] = h[j], h[i]
	h[i].index, h[j].index = i, j
}
func (h *broadcastExpiryHeap) Push(x any) {
	entry := x.(*broadcastExpiry)
	entry.index = len(*h)
	*h = append(*h, entry)
}
func (h *broadcastExpiryHeap) Pop() any {
	old := *h
	n := len(old)
	x := old[n-1]
	old[n-1] = nil
	x.index = -1
	*h = old[:n-1]
	return x
}

const (
	broadcastPending  = "pending"
	broadcastAccepted = "accepted"
	broadcastRejected = "rejected"
	broadcastUnknown  = "unknown"
)

var errBroadcastGuardUnavailable = errors.New("broadcast idempotency guard unavailable")

type broadcastRecord struct {
	State  string     `json:"state"`
	TxHash string     `json:"txHash,omitempty"`
	Error  *rpc.Error `json:"error,omitempty"`
}

type localBroadcastRecord struct {
	record    broadcastRecord
	expires   time.Time
	expiry    *broadcastExpiry
	evictable *list.Element
}

type broadcastGuardMetrics struct {
	claimAcquired  atomic.Uint64
	replayAccepted atomic.Uint64
	replayRejected atomic.Uint64
	replayUnknown  atomic.Uint64
	replayPending  atomic.Uint64
	unavailable    atomic.Uint64
	corruptRecord  atomic.Uint64
	persistError   atomic.Uint64
}

type broadcastGuardMetricSnapshot struct {
	ClaimAcquired  uint64
	ReplayAccepted uint64
	ReplayRejected uint64
	ReplayUnknown  uint64
	ReplayPending  uint64
	Unavailable    uint64
	CorruptRecord  uint64
	PersistError   uint64
}

// broadcastGuard coordinates exact signed-payload submissions. With Redis it
// is process- and instance-safe; without Redis (tests/development) it still
// prevents duplicate work within one Gateway process.
type broadcastGuard struct {
	clk    clock.Clock
	shared cache.AtomicStore

	mu        sync.Mutex
	records   map[string]localBroadcastRecord
	expiries  broadcastExpiryHeap
	evictable list.List
	metrics   broadcastGuardMetrics
}

func newBroadcastGuard(clk clock.Clock, shared cache.AtomicStore) *broadcastGuard {
	return &broadcastGuard{
		clk:     clk,
		shared:  shared,
		records: make(map[string]localBroadcastRecord),
	}
}

// begin returns owner=true only to the caller allowed to contact an upstream.
// A process-local pending reservation closes the same-process race before the
// Redis claim without serializing unrelated wallets behind shared-store I/O.
func (g *broadcastGuard) begin(
	ctx context.Context,
	key string,
) (record broadcastRecord, owner bool, err error) {
	g.mu.Lock()
	now := g.clk.Now()
	for budget := broadcastExpirySweepBudget; budget > 0 && len(g.expiries) > 0; budget-- {
		if g.expiries[0].at.After(now) {
			break
		}
		g.removeLocal(g.expiries[0].key)
	}
	if existing, ok := g.records[key]; ok {
		if existing.expires.After(now) {
			if existing.evictable != nil {
				g.evictable.MoveToBack(existing.evictable)
			}
			g.mu.Unlock()
			if !validBroadcastRecord(existing.record) {
				g.metrics.corruptRecord.Add(1)
				return broadcastRecord{}, false, errBroadcastGuardUnavailable
			}
			g.recordReplay(existing.record)
			return existing.record, false, nil
		}
		g.removeLocal(key)
	}
	if len(g.records) >= maxBroadcastRecords && g.evictable.Len() > 0 {
		g.removeLocal(g.evictable.Front().Value.(string))
	}
	if len(g.records) >= maxBroadcastRecords {
		g.mu.Unlock()
		// Even when every local slot is pinned by an in-flight/uncertain write,
		// a peer's existing result remains readable without acquiring new work.
		if g.shared != nil {
			if record, readErr := g.readShared(ctx, key); readErr == nil {
				g.recordReplay(record)
				return record, false, nil
			}
		}
		g.metrics.unavailable.Add(1)
		return broadcastRecord{}, false, errBroadcastGuardUnavailable
	}

	pending := broadcastRecord{State: broadcastPending}
	expiry := &broadcastExpiry{key: key, at: now.Add(broadcastGuardTTL)}
	g.records[key] = localBroadcastRecord{
		record: pending, expires: expiry.at, expiry: expiry,
	}
	heap.Push(&g.expiries, expiry)
	g.mu.Unlock()

	if g.shared != nil {
		raw, marshalErr := json.Marshal(pending)
		if marshalErr != nil {
			g.releaseUnsubmitted(key)
			g.metrics.unavailable.Add(1)
			return broadcastRecord{}, false, errBroadcastGuardUnavailable
		}
		created, setErr := g.shared.SetNX(ctx, key, raw, broadcastGuardTTL)
		if setErr != nil {
			// No upstream call has happened. An ambiguous SetNX is safe to retry:
			// Redis will still arbitrate any claim that actually reached it.
			g.releaseUnsubmitted(key)
			g.metrics.unavailable.Add(1)
			return broadcastRecord{}, false, fmt.Errorf(
				"%w: %v", errBroadcastGuardUnavailable, setErr,
			)
		}
		if !created {
			existing, readErr := g.readShared(ctx, key)
			if readErr != nil {
				g.releaseUnsubmitted(key)
				return broadcastRecord{}, false, readErr
			}
			g.mu.Lock()
			// Retain the reservation's fixed expiry. Replays/completion must not
			// grow the expiry index or extend records forever.
			entry, ok := g.records[key]
			if !ok {
				g.mu.Unlock()
				return broadcastRecord{}, false, errBroadcastGuardUnavailable
			}
			entry.record = existing
			g.records[key] = entry
			if existing.State == broadcastPending {
				// A peer can complete immediately after this read. Never freeze
				// its pending snapshot in this process for the full 24h window.
				g.removeLocal(key)
			} else {
				g.markEvictable(key)
			}
			g.mu.Unlock()
			g.recordReplay(existing)
			return existing, false, nil
		}
	}
	g.metrics.claimAcquired.Add(1)
	return pending, true, nil
}

// complete publishes the authoritative result after the single upstream
// attempt. A Redis failure is observable to the caller, but the local record
// remains installed so this process still will not replay the transaction.
func (g *broadcastGuard) complete(
	ctx context.Context,
	key string,
	record broadcastRecord,
) error {
	if !validBroadcastRecord(record) || record.State == broadcastPending {
		g.metrics.persistError.Add(1)
		return errors.New("invalid terminal broadcast record")
	}
	g.mu.Lock()
	entry, ok := g.records[key]
	if !ok {
		g.mu.Unlock()
		g.metrics.persistError.Add(1)
		return errBroadcastGuardUnavailable
	}
	entry.record = record
	g.records[key] = entry
	if g.shared == nil && record.State == broadcastRejected {
		g.markEvictable(key)
	}
	g.mu.Unlock()
	if g.shared == nil {
		return nil
	}
	raw, err := json.Marshal(record)
	if err != nil {
		g.metrics.persistError.Add(1)
		return err
	}
	if err := g.shared.Set(ctx, key, raw, broadcastGuardTTL); err != nil {
		g.metrics.persistError.Add(1)
		if record.State == broadcastRejected {
			g.mu.Lock()
			if current, ok := g.records[key]; ok && current.expiry == entry.expiry {
				g.markEvictable(key)
			}
			g.mu.Unlock()
		}
		return err
	}
	g.mu.Lock()
	if current, ok := g.records[key]; ok && current.expiry == entry.expiry {
		g.markEvictable(key)
	}
	g.mu.Unlock()
	return nil
}

// These helpers require mu. Removing the heap node as well as the map entry
// prevents a stream of evicted results from creating an unbounded expiry heap.
func (g *broadcastGuard) removeLocal(key string) {
	entry, ok := g.records[key]
	if !ok {
		return
	}
	if entry.evictable != nil {
		g.evictable.Remove(entry.evictable)
	}
	heap.Remove(&g.expiries, entry.expiry.index)
	delete(g.records, key)
}

func (g *broadcastGuard) markEvictable(key string) {
	entry, ok := g.records[key]
	if !ok || entry.evictable != nil {
		return
	}
	entry.evictable = g.evictable.PushBack(key)
	g.records[key] = entry
}

func (g *broadcastGuard) releaseUnsubmitted(key string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.removeLocal(key)
}

func (g *broadcastGuard) readShared(ctx context.Context, key string) (broadcastRecord, error) {
	raw, err := g.shared.Get(ctx, key)
	if err != nil {
		g.metrics.unavailable.Add(1)
		return broadcastRecord{}, fmt.Errorf("%w: %v", errBroadcastGuardUnavailable, err)
	}
	var record broadcastRecord
	if json.Unmarshal(raw, &record) != nil || !validBroadcastRecord(record) {
		g.metrics.corruptRecord.Add(1)
		return broadcastRecord{}, errBroadcastGuardUnavailable
	}
	return record, nil
}

func (g *broadcastGuard) recordReplay(record broadcastRecord) {
	switch record.State {
	case broadcastAccepted:
		g.metrics.replayAccepted.Add(1)
	case broadcastRejected:
		g.metrics.replayRejected.Add(1)
	case broadcastUnknown:
		g.metrics.replayUnknown.Add(1)
	case broadcastPending:
		g.metrics.replayPending.Add(1)
	}
}

func (g *broadcastGuard) metricSnapshot() broadcastGuardMetricSnapshot {
	return broadcastGuardMetricSnapshot{
		ClaimAcquired:  g.metrics.claimAcquired.Load(),
		ReplayAccepted: g.metrics.replayAccepted.Load(),
		ReplayRejected: g.metrics.replayRejected.Load(),
		ReplayUnknown:  g.metrics.replayUnknown.Load(),
		ReplayPending:  g.metrics.replayPending.Load(),
		Unavailable:    g.metrics.unavailable.Load(),
		CorruptRecord:  g.metrics.corruptRecord.Load(),
		PersistError:   g.metrics.persistError.Load(),
	}
}

func (g *broadcastGuard) sharedEnabled() bool {
	return g.shared != nil
}

func validBroadcastRecord(record broadcastRecord) bool {
	switch record.State {
	case broadcastPending:
		return record.TxHash == "" && record.Error == nil
	case broadcastAccepted:
		return strings.TrimSpace(record.TxHash) != "" && record.Error == nil
	case broadcastRejected:
		return record.TxHash == "" && record.Error != nil &&
			record.Error.Code == rpc.CodeUpstream
	case broadcastUnknown:
		return record.TxHash == "" && record.Error != nil &&
			record.Error.Code == rpc.CodeSubmissionUnknown
	default:
		return false
	}
}

func broadcastGuardKey(chain, network string, canonicalPayload []byte) string {
	hash := sha256.New()
	_, _ = hash.Write([]byte(chain))
	_, _ = hash.Write([]byte{0})
	_, _ = hash.Write([]byte(network))
	_, _ = hash.Write([]byte{0})
	_, _ = hash.Write(canonicalPayload)
	return "ktw:v1:broadcast:" + hex.EncodeToString(hash.Sum(nil))
}

func replayBroadcast(record broadcastRecord, chain, network string) (any, *rpc.Error) {
	switch record.State {
	case broadcastAccepted:
		return acceptedBroadcastResult(chain, network, record.TxHash), nil
	case broadcastRejected, broadcastUnknown:
		if record.Error != nil {
			return nil, record.Error
		}
	}
	return nil, &rpc.Error{
		Code:    rpc.CodeSubmissionUnknown,
		Message: "submission_unknown",
		Data: map[string]string{
			"upstream": "gateway",
			"message":  "matching signed transaction is already being processed",
		},
	}
}

package handlers

import (
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
	record  broadcastRecord
	expires time.Time
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

	mu      sync.Mutex
	records map[string]localBroadcastRecord
	metrics broadcastGuardMetrics
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
	if len(g.records) > 4096 {
		for candidate, entry := range g.records {
			if !entry.expires.After(now) {
				delete(g.records, candidate)
			}
		}
	}
	if existing, ok := g.records[key]; ok {
		if existing.expires.After(now) {
			g.mu.Unlock()
			if !validBroadcastRecord(existing.record) {
				g.metrics.corruptRecord.Add(1)
				return broadcastRecord{}, false, errBroadcastGuardUnavailable
			}
			g.recordReplay(existing.record)
			return existing.record, false, nil
		}
		delete(g.records, key)
	}

	pending := broadcastRecord{State: broadcastPending}
	g.records[key] = localBroadcastRecord{
		record: pending, expires: now.Add(broadcastGuardTTL),
	}
	g.mu.Unlock()

	if g.shared != nil {
		raw, marshalErr := json.Marshal(pending)
		if marshalErr != nil {
			g.metrics.unavailable.Add(1)
			return broadcastRecord{}, false, errBroadcastGuardUnavailable
		}
		created, setErr := g.shared.SetNX(ctx, key, raw, broadcastGuardTTL)
		if setErr != nil {
			g.metrics.unavailable.Add(1)
			return broadcastRecord{}, false, fmt.Errorf(
				"%w: %v", errBroadcastGuardUnavailable, setErr,
			)
		}
		if !created {
			raw, getErr := g.shared.Get(ctx, key)
			if getErr != nil {
				g.metrics.unavailable.Add(1)
				return broadcastRecord{}, false, fmt.Errorf(
					"%w: %v", errBroadcastGuardUnavailable, getErr,
				)
			}
			var existing broadcastRecord
			if jsonErr := json.Unmarshal(raw, &existing); jsonErr != nil ||
				!validBroadcastRecord(existing) {
				g.metrics.corruptRecord.Add(1)
				return broadcastRecord{}, false, errBroadcastGuardUnavailable
			}
			g.mu.Lock()
			g.records[key] = localBroadcastRecord{
				record: existing, expires: now.Add(broadcastGuardTTL),
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
	g.records[key] = localBroadcastRecord{
		record: record, expires: g.clk.Now().Add(broadcastGuardTTL),
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
		return err
	}
	return nil
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

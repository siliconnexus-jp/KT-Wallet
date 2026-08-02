// Package cache provides a small in-memory TTL cache with an injectable clock.
package cache

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sync"
	"sync/atomic"
	"time"

	"ktwallet/gateway/internal/clock"
)

// ErrNotFound is returned by a shared store when a key is absent.
var ErrNotFound = errors.New("cache key not found")

const maxSharedValueBytes = 1 << 20

// Store is the minimal shared-cache contract. Implementations must not log
// keys or values: values contain wallet balances/history and raw keys contain
// addresses before Cache hashes them.
type Store interface {
	Get(context.Context, string) ([]byte, error)
	Set(context.Context, string, []byte, time.Duration) error
}

// AtomicStore extends Store with the one primitive required by irreversible
// transaction submission. SetNX must atomically create key only when it does
// not already exist, across every Gateway process sharing the store.
//
// Read caches deliberately degrade to a miss when Redis is unavailable. A
// broadcast guard does not: without an atomic claim it cannot prove that a
// peer process is not already submitting the same signed transaction.
type AtomicStore interface {
	Store
	SetNX(context.Context, string, []byte, time.Duration) (bool, error)
}

// Codec serializes one cache's concrete value type for the shared layer.
// Local-only caches do not need one.
type Codec struct {
	Encode func(any) ([]byte, error)
	Decode func([]byte) (any, error)
}

// JSONPointerCodec preserves the pointer-shaped values used by Gateway
// handlers while keeping cache package independent of handler types.
func JSONPointerCodec[T any]() Codec {
	return Codec{
		Encode: json.Marshal,
		Decode: func(raw []byte) (any, error) {
			var value T
			if err := json.Unmarshal(raw, &value); err != nil {
				return nil, err
			}
			return &value, nil
		},
	}
}

type entry struct {
	value   any
	expires time.Time
}

// Cache is a TTL-bounded key/value map. Expired entries are evicted lazily on
// read and opportunistically on write.
type Cache struct {
	clk clock.Clock
	ttl time.Duration

	shared    Store
	namespace string
	codec     Codec
	hits      atomic.Uint64
	misses    atomic.Uint64
	errors    atomic.Uint64

	mu sync.Mutex
	m  map[string]entry
}

// New returns a Cache whose entries live for ttl.
func New(clk clock.Clock, ttl time.Duration) *Cache {
	return &Cache{clk: clk, ttl: ttl, m: make(map[string]entry)}
}

// NewShared returns a local-first cache backed by a shared store. Shared keys
// are SHA-256 fingerprints, so addresses and token sets are never visible in
// Redis key listings. Corrupt/unavailable shared data degrades to an ordinary
// local miss; it can never become transaction state or an authorization input.
func NewShared(clk clock.Clock, ttl time.Duration, store Store, namespace string, codec Codec) *Cache {
	if store == nil || namespace == "" || codec.Encode == nil || codec.Decode == nil {
		return New(clk, ttl)
	}
	return &Cache{
		clk:       clk,
		ttl:       ttl,
		shared:    store,
		namespace: namespace,
		codec:     codec,
		m:         make(map[string]entry),
	}
}

// Get returns the value stored under key if it has not expired.
func (c *Cache) Get(key string) (any, bool) {
	return c.GetContext(context.Background(), key)
}

// GetContext checks the process-local cache first, then the optional shared
// layer. The caller's cancellation/deadline bounds shared I/O.
func (c *Cache) GetContext(ctx context.Context, key string) (any, bool) {
	c.mu.Lock()
	e, ok := c.m[key]
	if ok && c.clk.Now().After(e.expires) {
		delete(c.m, key)
		ok = false
	}
	c.mu.Unlock()
	if ok {
		return e.value, true
	}
	if c.shared == nil {
		return nil, false
	}

	raw, err := c.shared.Get(ctx, c.sharedKey(key))
	if errors.Is(err, ErrNotFound) {
		c.misses.Add(1)
		return nil, false
	}
	if err != nil {
		c.errors.Add(1)
		return nil, false
	}
	if len(raw) > maxSharedValueBytes {
		c.errors.Add(1)
		return nil, false
	}
	var record sharedRecord
	if err := json.Unmarshal(raw, &record); err != nil {
		c.errors.Add(1)
		return nil, false
	}
	expires := time.UnixMilli(record.ExpiresAtMs)
	if !expires.After(c.clk.Now()) {
		c.misses.Add(1)
		return nil, false
	}
	value, err := c.codec.Decode(record.Value)
	if err != nil {
		c.errors.Add(1)
		return nil, false
	}
	c.setLocal(key, value, expires)
	c.hits.Add(1)
	return value, true
}

// Set stores value under key with the cache's TTL.
func (c *Cache) Set(key string, value any) {
	c.SetContext(context.Background(), key, value)
}

// SetContext updates the local layer and then best-effort writes the shared
// layer. A Redis outage never breaks wallet reads; it is exposed via Stats.
func (c *Cache) SetContext(ctx context.Context, key string, value any) {
	now := c.clk.Now()
	expires := now.Add(c.ttl)
	c.setLocal(key, value, expires)
	if c.shared == nil {
		return
	}
	payload, err := c.codec.Encode(value)
	if err != nil {
		c.errors.Add(1)
		return
	}
	record, err := json.Marshal(sharedRecord{
		ExpiresAtMs: expires.UnixMilli(),
		Value:       payload,
	})
	if err != nil {
		c.errors.Add(1)
		return
	}
	if len(record) > maxSharedValueBytes {
		c.errors.Add(1)
		return
	}
	if err := c.shared.Set(ctx, c.sharedKey(key), record, c.ttl); err != nil {
		c.errors.Add(1)
	}
}

func (c *Cache) setLocal(key string, value any, expires time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	// Opportunistic sweep to bound memory: drop expired entries when the map
	// grows moderately large.
	if len(c.m) > 4096 {
		for k, e := range c.m {
			if c.clk.Now().After(e.expires) {
				delete(c.m, k)
			}
		}
	}
	c.m[key] = entry{value: value, expires: expires}
}

// Len reports the number of stored (possibly expired) entries. Test helper.
func (c *Cache) Len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.m)
}

// Stats reports only aggregate shared-cache outcomes; it never exposes keys.
func (c *Cache) Stats() Stats {
	return Stats{
		Hits:   c.hits.Load(),
		Misses: c.misses.Load(),
		Errors: c.errors.Load(),
	}
}

func (c *Cache) SharedEnabled() bool {
	return c.shared != nil
}

type Stats struct {
	Hits   uint64
	Misses uint64
	Errors uint64
}

type sharedRecord struct {
	ExpiresAtMs int64           `json:"expiresAtMs"`
	Value       json.RawMessage `json:"value"`
}

func (c *Cache) sharedKey(key string) string {
	digest := sha256.Sum256([]byte(c.namespace + "\x00" + key))
	return "ktw:v1:" + c.namespace + ":" + hex.EncodeToString(digest[:])
}

// Package cache provides a small in-memory TTL cache with an injectable clock.
package cache

import (
	"sync"
	"time"

	"ktwallet/gateway/internal/clock"
)

type entry struct {
	value   any
	expires time.Time
}

// Cache is a TTL-bounded key/value map. Expired entries are evicted lazily on
// read and opportunistically on write.
type Cache struct {
	clk clock.Clock
	ttl time.Duration

	mu sync.Mutex
	m  map[string]entry
}

// New returns a Cache whose entries live for ttl.
func New(clk clock.Clock, ttl time.Duration) *Cache {
	return &Cache{clk: clk, ttl: ttl, m: make(map[string]entry)}
}

// Get returns the value stored under key if it has not expired.
func (c *Cache) Get(key string) (any, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.m[key]
	if !ok {
		return nil, false
	}
	if c.clk.Now().After(e.expires) {
		delete(c.m, key)
		return nil, false
	}
	return e.value, true
}

// Set stores value under key with the cache's TTL.
func (c *Cache) Set(key string, value any) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.clk.Now()
	// Opportunistic sweep to bound memory: drop expired entries when the map
	// grows moderately large.
	if len(c.m) > 4096 {
		for k, e := range c.m {
			if now.After(e.expires) {
				delete(c.m, k)
			}
		}
	}
	c.m[key] = entry{value: value, expires: now.Add(c.ttl)}
}

// Len reports the number of stored (possibly expired) entries. Test helper.
func (c *Cache) Len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.m)
}

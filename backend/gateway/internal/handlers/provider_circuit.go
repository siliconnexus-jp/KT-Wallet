package handlers

import (
	"sync"
	"time"

	"ktwallet/gateway/internal/clock"
)

const (
	externalProviderFailureThreshold = 3
	externalProviderOpenDuration     = 30 * time.Second
)

// providerCircuit prevents an unavailable security provider from adding its
// full timeout to every wallet confirmation. It deliberately has no fallback
// result: callers still receive an upstream error and therefore render
// "unable to check", never a stale green/safe conclusion.
//
// After the open window, exactly one request is admitted as a half-open probe.
// The generation carried by each permit prevents a success that started before
// a concurrent circuit-opening failure from incorrectly closing the circuit.
type providerCircuit struct {
	mu sync.Mutex

	clk              clock.Clock
	failureThreshold int
	openDuration     time.Duration

	consecutiveFailures int
	openUntil           time.Time
	probeInFlight       bool
	generation          uint64
	shortCircuits       uint64
}

type providerPermit struct {
	generation uint64
	probe      bool
}

type providerCircuitSnapshot struct {
	Open          bool
	ProbeInFlight bool
	ShortCircuits uint64
}

func newProviderCircuit(clk clock.Clock) *providerCircuit {
	if clk == nil {
		clk = clock.Real{}
	}
	return &providerCircuit{
		clk:              clk,
		failureThreshold: externalProviderFailureThreshold,
		openDuration:     externalProviderOpenDuration,
	}
}

func (c *providerCircuit) allow() (providerPermit, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.openUntil.IsZero() {
		return providerPermit{generation: c.generation}, true
	}
	if c.clk.Now().Before(c.openUntil) || c.probeInFlight {
		c.shortCircuits++
		return providerPermit{}, false
	}
	c.probeInFlight = true
	return providerPermit{generation: c.generation, probe: true}, true
}

// finish records the outcome of an admitted provider call. countFailure must
// be false when the caller's own context was cancelled: abandoning a screen
// must not make the shared provider look unhealthy.
func (c *providerCircuit) finish(
	permit providerPermit,
	succeeded bool,
	countFailure bool,
) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if permit.generation != c.generation {
		return
	}
	if !succeeded && !countFailure {
		if permit.probe {
			c.probeInFlight = false
		}
		return
	}
	if succeeded {
		c.consecutiveFailures = 0
		c.openUntil = time.Time{}
		c.probeInFlight = false
		if permit.probe {
			c.generation++
		}
		return
	}

	if permit.probe {
		c.consecutiveFailures = c.failureThreshold
		c.openUntil = c.clk.Now().Add(c.openDuration)
		c.probeInFlight = false
		c.generation++
		return
	}
	c.consecutiveFailures++
	if c.consecutiveFailures >= c.failureThreshold {
		c.openUntil = c.clk.Now().Add(c.openDuration)
		c.probeInFlight = false
		c.generation++
	}
}

func (c *providerCircuit) snapshot() providerCircuitSnapshot {
	c.mu.Lock()
	defer c.mu.Unlock()
	return providerCircuitSnapshot{
		Open:          !c.openUntil.IsZero(),
		ProbeInFlight: c.probeInFlight,
		ShortCircuits: c.shortCircuits,
	}
}

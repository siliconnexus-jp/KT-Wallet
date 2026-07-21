// Package clock abstracts wall-clock time so caches, circuit breakers and
// rate limiters can be driven by a fake clock in tests.
package clock

import (
	"sync"
	"time"
)

// Clock supplies the current time.
type Clock interface {
	Now() time.Time
}

// Real is the production clock.
type Real struct{}

// Now returns time.Now().
func (Real) Now() time.Time { return time.Now() }

// Fake is a manually advanced clock for tests.
type Fake struct {
	mu sync.Mutex
	t  time.Time
}

// NewFake returns a Fake clock frozen at t.
func NewFake(t time.Time) *Fake { return &Fake{t: t} }

// Now returns the fake current time.
func (f *Fake) Now() time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.t
}

// Advance moves the fake clock forward by d.
func (f *Fake) Advance(d time.Duration) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.t = f.t.Add(d)
}

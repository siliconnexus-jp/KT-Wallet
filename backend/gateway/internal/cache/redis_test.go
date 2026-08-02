package cache

import (
	"context"
	"errors"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func TestRedisStoreRequiresTLSOutsideLoopback(t *testing.T) {
	for _, rawURL := range []string{
		"redis://cache.internal:6379/0",
		"redis://203.0.113.8:6379/0",
		"http://localhost:6379",
	} {
		if store, err := NewRedisStore(rawURL); err == nil {
			_ = store.Close()
			t.Fatalf("expected unsafe URL rejection: %s", rawURL)
		}
	}
}

func TestRedisStoreAcceptsTLSAndLoopbackDevelopmentURLs(t *testing.T) {
	for _, rawURL := range []string{
		"rediss://user:secret@cache.example:6380/0",
		"redis://localhost:6379/0",
		"redis://127.0.0.1:6379/1",
		"redis://[::1]:6379/2",
	} {
		store, err := NewRedisStore(rawURL)
		if err != nil {
			t.Fatalf("expected URL acceptance for %s: %v", rawURL, err)
		}
		_ = store.Close()
	}
}

func TestRedisStoreForcesFastFailOptions(t *testing.T) {
	store, err := NewRedisStore("redis://127.0.0.1:6379/0?dial_timeout=10s&read_timeout=10s&write_timeout=10s")
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	opts := store.client.Options()
	// go-redis normalizes -1 to zero internally; zero here means disabled.
	if opts.MaxRetries != 0 {
		t.Fatalf("shared cache retries = %d, want disabled", opts.MaxRetries)
	}
	if opts.DialerRetries != 1 {
		t.Fatalf("shared cache dial retries = %d, want 1", opts.DialerRetries)
	}
	for name, got := range map[string]time.Duration{
		"dial":  opts.DialTimeout,
		"read":  opts.ReadTimeout,
		"write": opts.WriteTimeout,
		"pool":  opts.PoolTimeout,
	} {
		if got != redisOperationTimeout {
			t.Fatalf("%s timeout = %v, want %v", name, got, redisOperationTimeout)
		}
	}
}

func TestRedisStoreCircuitSkipsRepeatedFailedDials(t *testing.T) {
	var dials atomic.Int32
	client := redis.NewClient(&redis.Options{
		Addr:          "unused.invalid:6379",
		MaxRetries:    -1,
		DialerRetries: 1,
		Dialer: func(context.Context, string, string) (net.Conn, error) {
			dials.Add(1)
			return nil, errors.New("offline")
		},
	})
	defer client.Close()
	now := time.Unix(1_700_000_000, 0)
	store := newRedisStore(client, func() time.Time { return now }, 5*time.Second)

	if _, err := store.Get(context.Background(), "fingerprint"); err == nil {
		t.Fatal("first failed dial must surface an error")
	}
	firstDials := dials.Load()
	if firstDials == 0 {
		t.Fatal("first operation did not attempt Redis")
	}
	if _, err := store.Get(context.Background(), "fingerprint"); !errors.Is(err, errRedisCircuitOpen) {
		t.Fatalf("second operation should short-circuit, got %v", err)
	}
	if got := dials.Load(); got != firstDials {
		t.Fatalf("open circuit dialed again: %d -> %d", firstDials, got)
	}

	now = now.Add(6 * time.Second)
	if _, err := store.Get(context.Background(), "fingerprint"); err == nil {
		t.Fatal("half-open probe should still observe the scripted outage")
	}
	if got := dials.Load(); got <= firstDials {
		t.Fatal("expired cooldown did not permit one recovery probe")
	}
}

func TestRedisStoreSuccessfulProbeClosesCircuit(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	store := newRedisStore(redis.NewClient(&redis.Options{Addr: "unused:6379"}), func() time.Time { return now }, 5*time.Second)
	defer store.Close()
	store.finishOperation(errors.New("offline"), false)
	if _, err := store.beginOperation(); !errors.Is(err, errRedisCircuitOpen) {
		t.Fatalf("freshly opened circuit should reject work, got %v", err)
	}
	now = now.Add(6 * time.Second)
	probe, err := store.beginOperation()
	if err != nil {
		t.Fatalf("cooldown should allow a probe: %v", err)
	}
	if !probe {
		t.Fatal("cooldown recovery operation was not marked as the half-open probe")
	}
	store.finishOperation(nil, probe)
	if probe, err := store.beginOperation(); err != nil || probe {
		t.Fatalf("successful probe should close circuit: %v", err)
	}
	store.finishOperation(nil, false)
}

func TestRedisStoreCallerCancellationDoesNotOpenCircuit(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	store := newRedisStore(redis.NewClient(&redis.Options{Addr: "unused:6379"}), func() time.Time { return now }, 5*time.Second)
	defer store.Close()
	store.finishOperation(context.Canceled, false)
	if _, err := store.beginOperation(); err != nil {
		t.Fatalf("caller cancellation opened the shared circuit: %v", err)
	}
	store.finishOperation(nil, false)

	store.finishOperation(errors.New("offline"), false)
	now = now.Add(6 * time.Second)
	probe, err := store.beginOperation()
	if err != nil {
		t.Fatalf("expired circuit should allow a probe: %v", err)
	}
	store.finishOperation(context.DeadlineExceeded, probe)
	probe, err = store.beginOperation()
	if err != nil {
		t.Fatalf("canceled half-open probe should permit another caller: %v", err)
	}
	store.finishOperation(nil, probe)
}

func TestRedisStoreStaleSuccessCannotCloseConcurrentFailureCircuit(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	store := newRedisStore(redis.NewClient(&redis.Options{Addr: "unused:6379"}), func() time.Time { return now }, 5*time.Second)
	defer store.Close()

	// Both operations began while the circuit was closed. The failure finishes
	// first and opens it; the older successful operation must not undo that
	// health evidence when it completes later.
	firstProbe, err := store.beginOperation()
	if err != nil || firstProbe {
		t.Fatalf("first ordinary operation did not start: probe=%v err=%v", firstProbe, err)
	}
	secondProbe, err := store.beginOperation()
	if err != nil || secondProbe {
		t.Fatalf("second ordinary operation did not start: probe=%v err=%v", secondProbe, err)
	}
	store.finishOperation(errors.New("offline"), secondProbe)
	store.finishOperation(nil, firstProbe)

	if _, err := store.beginOperation(); !errors.Is(err, errRedisCircuitOpen) {
		t.Fatalf("stale success closed the failure circuit: %v", err)
	}
}

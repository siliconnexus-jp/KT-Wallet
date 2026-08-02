package cache

import (
	"context"
	"errors"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisStore is the production shared-cache adapter. REDIS_URL may use redis
// or rediss; authentication and TLS are parsed by go-redis and are never
// exposed by this type.
type RedisStore struct {
	client *redis.Client

	mu            sync.Mutex
	openUntil     time.Time
	halfOpenProbe bool
	now           func() time.Time
	cooldown      time.Duration
}

var _ AtomicStore = (*RedisStore)(nil)

var errRedisCircuitOpen = errors.New("shared cache circuit open")

const (
	redisOperationTimeout = 750 * time.Millisecond
	redisFailureCooldown  = 5 * time.Second
)

func NewRedisStore(rawURL string) (*RedisStore, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, errors.New("invalid redis URL")
	}
	if parsed.Scheme == "redis" && !isLoopbackHost(parsed.Hostname()) {
		return nil, errors.New("remote shared cache must use rediss TLS")
	}
	if parsed.Scheme != "redis" && parsed.Scheme != "rediss" {
		return nil, errors.New("redis URL must use redis or rediss")
	}
	opts, err := redis.ParseURL(rawURL)
	if err != nil {
		return nil, errors.New("invalid redis URL")
	}
	// Shared caching is optional and must never add multi-second retry stalls
	// to a wallet balance/history request. The Gateway performs its own
	// short-circuiting, so go-redis retries are disabled and all I/O is tightly
	// bounded even if an operator supplied looser URL query options.
	opts.MaxRetries = -1
	opts.DialerRetries = 1
	opts.DialerRetryTimeout = 10 * time.Millisecond
	opts.DialTimeout = redisOperationTimeout
	opts.ReadTimeout = redisOperationTimeout
	opts.WriteTimeout = redisOperationTimeout
	opts.PoolTimeout = redisOperationTimeout
	return newRedisStore(redis.NewClient(opts), time.Now, redisFailureCooldown), nil
}

func newRedisStore(client *redis.Client, now func() time.Time, cooldown time.Duration) *RedisStore {
	if now == nil {
		now = time.Now
	}
	if cooldown <= 0 {
		cooldown = redisFailureCooldown
	}
	return &RedisStore{client: client, now: now, cooldown: cooldown}
}

func isLoopbackHost(host string) bool {
	switch strings.ToLower(host) {
	case "localhost", "127.0.0.1", "::1":
		return true
	default:
		return false
	}
}

func (s *RedisStore) Ping(ctx context.Context) error {
	probe, err := s.beginOperation()
	if err != nil {
		return err
	}
	err = s.client.Ping(ctx).Err()
	s.finishOperation(err, probe)
	return err
}

func (s *RedisStore) Get(ctx context.Context, key string) ([]byte, error) {
	probe, err := s.beginOperation()
	if err != nil {
		return nil, err
	}
	raw, err := s.client.Get(ctx, key).Bytes()
	if err == redis.Nil {
		s.finishOperation(nil, probe)
		return nil, ErrNotFound
	}
	s.finishOperation(err, probe)
	return raw, err
}

func (s *RedisStore) Set(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	probe, err := s.beginOperation()
	if err != nil {
		return err
	}
	err = s.client.Set(ctx, key, value, ttl).Err()
	s.finishOperation(err, probe)
	return err
}

// SetNX atomically claims key for cross-process coordination. It inherits the
// same bounded, retry-disabled Redis policy as ordinary cache operations so an
// uncertain Redis write can never be silently replayed by this client.
func (s *RedisStore) SetNX(
	ctx context.Context,
	key string,
	value []byte,
	ttl time.Duration,
) (bool, error) {
	probe, err := s.beginOperation()
	if err != nil {
		return false, err
	}
	created, err := s.client.SetNX(ctx, key, value, ttl).Result()
	s.finishOperation(err, probe)
	return created, err
}

func (s *RedisStore) Close() error {
	return s.client.Close()
}

// beginOperation returns whether the caller owns the single half-open recovery
// probe. Ordinary operations that started while the circuit was closed must
// not later close a circuit opened by a concurrent failure.
func (s *RedisStore) beginOperation() (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	if s.openUntil.IsZero() {
		return false, nil
	}
	if now.Before(s.openUntil) || s.halfOpenProbe {
		return false, errRedisCircuitOpen
	}
	s.halfOpenProbe = true
	return true, nil
}

func (s *RedisStore) finishOperation(err error, probe bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if probe {
		s.halfOpenProbe = false
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		// A caller disconnect or exhausted request budget says nothing about
		// Redis health and must not degrade cache service for other clients.
		return
	}
	if err == nil {
		if probe {
			s.openUntil = time.Time{}
		}
		return
	}
	// Any Redis-originated failure opens or refreshes the circuit. This also
	// wins over a stale success from an operation that began before the failure.
	s.openUntil = s.now().Add(s.cooldown)
}

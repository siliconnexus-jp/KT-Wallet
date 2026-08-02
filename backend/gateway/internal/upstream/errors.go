package upstream

import (
	"context"
	"errors"
	"io"
	"strings"
)

var errResponseTooLarge = errors.New("upstream response exceeds size limit")

// readBoundedResponse reads the complete response only when it fits within
// maxBytes. Reading max+1 is intentional: io.LimitReader at exactly the limit
// cannot distinguish an exact-size response from a truncated larger response.
// Returning nil on overflow prevents callers from accidentally accepting a
// valid JSON prefix followed by an unbounded whitespace or padding body.
func readBoundedResponse(body io.Reader, maxBytes int64) ([]byte, error) {
	if maxBytes < 0 {
		return nil, errResponseTooLarge
	}
	data, err := io.ReadAll(io.LimitReader(body, maxBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > maxBytes {
		return nil, errResponseTooLarge
	}
	return data, nil
}

// safeRequestFailure deliberately discards the underlying net/http error.
// Go transport errors commonly embed the complete request URL, and provider
// credentials are carried in URL paths or query parameters by several RPC
// vendors. Those details must never enter an Unavailable value that can cross
// the public JSON-RPC boundary.
func safeRequestFailure(upstream string, ctx context.Context, err error) *Unavailable {
	switch {
	case errors.Is(err, context.DeadlineExceeded), errors.Is(ctx.Err(), context.DeadlineExceeded):
		return &Unavailable{Upstream: upstream, Message: "upstream request timed out"}
	case errors.Is(err, context.Canceled), errors.Is(ctx.Err(), context.Canceled):
		return &Unavailable{Upstream: upstream, Message: "upstream request canceled"}
	default:
		return &Unavailable{Upstream: upstream, Message: "upstream request failed"}
	}
}

func safeRequestCreationFailure(upstream string) *Unavailable {
	return &Unavailable{Upstream: upstream, Message: "could not create upstream request"}
}

func safeResponseReadFailure(upstream string) *Unavailable {
	return &Unavailable{Upstream: upstream, Message: "could not read upstream response"}
}

// PublicNodeErrorMessage maps an untrusted provider message to a small,
// bounded vocabulary. Besides keeping UX actionable for common transaction
// failures, this prevents a provider from reflecting credentials, URLs,
// control characters, or an oversized response through the Gateway API.
func PublicNodeErrorMessage(message string) string {
	lower := strings.ToLower(message)
	for _, item := range []struct {
		contains string
		public   string
	}{
		{"insufficient funds", "insufficient funds for transaction"},
		{"nonce too low", "transaction nonce is too low"},
		{"nonce too high", "transaction nonce is too high"},
		{"replacement transaction underpriced", "replacement transaction fee is too low"},
		{"transaction underpriced", "transaction fee is too low"},
		{"intrinsic gas too low", "transaction gas limit is too low"},
		{"exceeds block gas limit", "transaction exceeds the block gas limit"},
		{"fee cap less than block base fee", "transaction fee cap is below the network base fee"},
		{"already known", "transaction is already known by the network"},
		{"execution reverted", "transaction execution reverted"},
		{"invalid sender", "transaction sender is invalid"},
		{"blockhash not found", "transaction blockhash is no longer valid"},
		{"account in use", "transaction account is currently in use"},
		{"transaction simulation failed", "transaction simulation failed"},
		{"signature verification failed", "transaction signature verification failed"},
		{"validate signature", "transaction signature verification failed"},
		{"signature error", "transaction signature verification failed"},
		{"rate limit", "upstream rate limit reached"},
		{"too many requests", "upstream rate limit reached"},
	} {
		if strings.Contains(lower, item.contains) {
			return item.public
		}
	}
	return "upstream rejected request"
}

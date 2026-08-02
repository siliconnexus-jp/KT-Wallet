package handlers

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"ktwallet/gateway/internal/upstream"
)

func TestPublicErrorBoundariesNeverReflectProviderSecrets(t *testing.T) {
	const secret = "https://rpc.example.invalid/v2/provider-secret"
	tests := []struct {
		name string
		err  error
		mapf func(string, error) map[string]any
	}{
		{
			name: "read unavailable",
			err:  &upstream.Unavailable{Upstream: secret, Message: "dial " + secret},
			mapf: func(fallback string, err error) map[string]any {
				mapped := upstreamError(fallback, err)
				return map[string]any{"message": mapped.Message, "data": mapped.Data}
			},
		},
		{
			name: "read generic",
			err:  errors.New("dial " + secret),
			mapf: func(fallback string, err error) map[string]any {
				mapped := upstreamError(fallback, err)
				return map[string]any{"message": mapped.Message, "data": mapped.Data}
			},
		},
		{
			name: "broadcast unavailable",
			err:  &upstream.Unavailable{Upstream: secret, Message: "dial " + secret},
			mapf: func(fallback string, err error) map[string]any {
				mapped := broadcastError(fallback, err)
				return map[string]any{"message": mapped.Message, "data": mapped.Data}
			},
		},
		{
			name: "node response",
			err:  &upstream.NodeError{Code: -32000, Message: "provider failed at " + secret},
			mapf: func(fallback string, err error) map[string]any {
				mapped := upstreamError(fallback, err)
				return map[string]any{"message": mapped.Message, "data": mapped.Data}
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			mapped := tc.mapf("eth", tc.err)
			if strings.Contains(toJSONForPrivacyTest(t, mapped), secret) {
				t.Fatalf("public error reflected provider secret: %#v", mapped)
			}
		})
	}
}

func toJSONForPrivacyTest(t *testing.T, value any) string {
	t.Helper()
	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return strings.ReplaceAll(strings.TrimSpace(string(encoded)), "\\/", "/")
}

package upstream

import (
	"errors"
	"strings"
	"testing"
)

func TestReadBoundedResponseRejectsValidPrefixWithOversizedTrailingWhitespace(t *testing.T) {
	const limit = int64(32)
	body := `{"jsonrpc":"2.0","result":1}` + strings.Repeat(" ", 32)
	data, err := readBoundedResponse(strings.NewReader(body), limit)
	if !errors.Is(err, errResponseTooLarge) {
		t.Fatalf("error = %v, want errResponseTooLarge", err)
	}
	if data != nil {
		t.Fatalf("oversized response data must be discarded, got %d bytes", len(data))
	}
}

func TestReadBoundedResponseAcceptsExactLimit(t *testing.T) {
	const body = `{"jsonrpc":"2.0","result":1}`
	data, err := readBoundedResponse(strings.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != body {
		t.Fatalf("data = %q, want %q", data, body)
	}
}

package upstream

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestTronAPIKeyHeaders(t *testing.T) {
	const key = "test-only-trongrid-key"
	for _, configured := range []string{"", key} {
		for _, method := range []string{http.MethodGet, http.MethodPost} {
			t.Run(fmt.Sprintf("key=%t/%s", configured != "", method), func(t *testing.T) {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if r.Header.Get("TRON-PRO-API-KEY") != configured {
						t.Error("unexpected credential header")
					}
					if strings.Contains(r.URL.String(), key) {
						t.Error("credential appeared in URL")
					}
					w.Write([]byte(`{"ok":true}`))
				}))
				defer server.Close()
				client := NewTronWithAPIKey(server.URL, configured, server.Client(), time.Second)
				if _, err := client.fetch(context.Background(), method, "/probe", nil); err != nil {
					t.Fatal(err)
				}
			})
		}
	}
}

func TestTronAPIKeyCannotFollowRedirectOrChangeSharedClient(t *testing.T) {
	var forwarded atomic.Bool
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		forwarded.Store(true)
	}))
	defer target.Close()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusTemporaryRedirect)
	}))
	defer origin.Close()
	shared := origin.Client()
	client := NewTronWithAPIKey(origin.URL, "test-only-key", shared, time.Second)
	if _, err := client.fetch(context.Background(), http.MethodGet, "/probe", nil); err == nil {
		t.Fatal("redirect should fail closed")
	}
	if forwarded.Load() || shared.CheckRedirect != nil {
		t.Fatal("credential forwarded or shared client mutated")
	}
}

func TestTronAPIKeyTransportFailureIsRedacted(t *testing.T) {
	const key = "test-only-sensitive-header"
	httpClient := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		return nil, fmt.Errorf("provider error includes %s", r.Header.Get("TRON-PRO-API-KEY"))
	})}
	client := NewTronWithAPIKey("https://tron.example.invalid", key, httpClient, time.Second)
	_, err := client.fetch(context.Background(), http.MethodGet, "/probe", nil)
	if err == nil || strings.Contains(err.Error(), key) {
		t.Fatal("missing failure or unredacted credential")
	}
}

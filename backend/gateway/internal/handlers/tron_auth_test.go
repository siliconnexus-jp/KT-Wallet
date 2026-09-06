package handlers_test

import (
	"net/http"
	"testing"

	"ktwallet/gateway/internal/handlers"
)

func TestTronAPIKeyIsMainnetOnly(t *testing.T) {
	mainnet, nile := newRESTFake(t), newRESTFake(t)
	const key = "test-only-mainnet-credential"
	for _, endpoint := range []struct {
		fake *restFake
		want string
	}{{mainnet, key}, {nile, ""}} {
		endpoint.fake.route("/v1/accounts/", func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("TRON-PRO-API-KEY") != endpoint.want {
				t.Error("wrong credential scope")
			}
			w.Header().Set("Content-Type", "application/json")
			w.Write([]byte(`{"data":[],"success":true}`))
		})
	}
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TronURL = mainnet.srv.URL
		cfg.TronNileURL = nile.srv.URL
		cfg.TronAPIKey = key
	})
	for _, network := range []string{"tron-mainnet", "tron-nile"} {
		result(t, e.rpc("kt_getBalances", map[string]any{
			"chain": "tron", "network": network,
			"address": "T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb",
		}))
	}
	if mainnet.hitCount("/v1/accounts/") == 0 || nile.hitCount("/v1/accounts/") == 0 {
		t.Fatal("both networks must be exercised")
	}
}

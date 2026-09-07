package handlers_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

const feeAddress = "T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb"

func TestTronFeeReadsAuthenticatedAndNetworkScoped(t *testing.T) {
	mainnet, nile := newRESTFake(t), newRESTFake(t)
	for _, endpoint := range []struct {
		fake *restFake
		key  string
	}{{mainnet, "server-only"}, {nile, ""}} {
		endpoint.fake.route("/", func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("TRON-PRO-API-KEY") != endpoint.key {
				t.Error("wrong credential scope")
			}
			if r.URL.Path == "/v1/accounts/"+feeAddress {
				if r.Method != http.MethodGet {
					t.Error("account must be GET")
				}
			} else {
				if r.Method != http.MethodPost {
					t.Error("fee reads must be POST")
				}
				if r.URL.Path == "/wallet/triggerconstantcontract" {
					var body map[string]any
					json.NewDecoder(r.Body).Decode(&body)
					if body["visible"] != true || body["owner_address"] != feeAddress || body["contract_address"] != feeAddress {
						t.Error("unbound constant call")
					}
				}
			}
			w.Write([]byte(`{"result":{"result":true},"energy_used":130000}`))
		})
	}
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TronURL, cfg.TronNileURL, cfg.TronAPIKey = mainnet.srv.URL, nile.srv.URL, "server-only"
	})
	for _, network := range []string{"tron-mainnet", "tron-nile"} {
		for _, op := range []string{"account", "block", "resources", "parameters", "constant"} {
			p := map[string]any{"network": network, "operation": op}
			if op == "account" || op == "resources" || op == "constant" {
				p["address"] = feeAddress
			}
			if op == "constant" {
				p["contract"], p["selector"], p["parameter"] = feeAddress, "transfer(address,uint256)", strings.Repeat("0", 127)+"1"
			}
			res := result(t, e.rpc("kt_getTronFeeData", p))
			if res["network"] != network || res["operation"] != op || res["data"] == nil {
				t.Fatal("unbound fee result")
			}
		}
	}
}

func TestTronFeeRejectsUnsafeReadsBeforeUpstream(t *testing.T) {
	grid := newRESTFake(t)
	grid.route("/", func(w http.ResponseWriter, r *http.Request) { t.Error("invalid read reached upstream") })
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })
	for _, params := range []string{
		`{"operation":"broadcast"}`,
		`{"operation":"block","url":"https://evil.invalid"}`,
		`{"operation":"block","network":"eth-mainnet"}`,
		`{"operation":"block","address":"` + feeAddress + `"}`,
		`{"operation":"account","address":"../wallet/broadcasttransaction"}`,
		`{"operation":"constant","address":"` + feeAddress + `","contract":"` + feeAddress + `","selector":"approve(address,uint256)","parameter":"` + strings.Repeat("0", 128) + `"}`,
		`{"operation":"constant","address":"` + feeAddress + `","contract":"` + feeAddress + `","selector":"balanceOf(address)","parameter":"` + strings.Repeat("f", 64) + `"}`,
		`{"operation":"block","operation":"parameters"}`,
	} {
		assertErrCode(t, e.rpc("kt_getTronFeeData", params), rpc.CodeInvalidParams)
	}
}

func TestTronFeeProviderFailuresAreNotEmptyAccounts(t *testing.T) {
	for _, status := range []int{200, 403, 429, 500} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			grid := newRESTFake(t)
			grid.route("/", func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(status)
				w.Write([]byte(`{"Error":"private-provider-secret"}`))
			})
			e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })
			resp := e.rpc("kt_getTronFeeData", map[string]any{"operation": "account", "address": feeAddress})
			want := rpc.CodeUpstream
			if status == 403 || status == 429 {
				want = rpc.CodeRateLimited
			}
			assertErrCode(t, resp, want)
			encoded, _ := json.Marshal(resp)
			if strings.Contains(string(encoded), "private-provider-secret") {
				t.Fatal("provider text leaked")
			}
		})
	}
}

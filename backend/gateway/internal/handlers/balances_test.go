package handlers_test

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

// scriptEVMBalances wires eth_getBalance -> 1 ETH and eth_call balanceOf
// responses keyed by contract address.
func scriptEVMBalances(f *rpcFake, perContract map[string]string) {
	f.result("eth_getBalance", "0xde0b6b3a7640000") // 1e18
	f.handle("eth_call", func(params []json.RawMessage) (any, map[string]any) {
		var call struct {
			To   string `json:"to"`
			Data string `json:"data"`
		}
		_ = json.Unmarshal(params[0], &call)
		if res, ok := perContract[strings.ToLower(call.To)]; ok {
			return res, nil
		}
		return nil, map[string]any{"code": -32000, "message": "execution reverted"}
	})
}

func balancesParams(chain, address string, tokens string) string {
	if tokens == "" {
		return fmt.Sprintf(`{"chain":%q,"address":%q}`, chain, address)
	}
	return fmt.Sprintf(`{"chain":%q,"address":%q,"tokens":%s}`, chain, address, tokens)
}

func TestEVMBalancesGolden(t *testing.T) {
	node := newRPCFake(t)
	scriptEVMBalances(node, map[string]string{
		evmTokenA: "0x00000000000000000000000000000000000000000000000000000000000f4240", // 1_000_000
		evmTokenB: "0x",                                                                 // empty return == zero
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_getBalances", balancesParams("eth", evmSelf,
		fmt.Sprintf(`[{"contract":%q,"decimals":6,"symbol":"USDT"},{"contract":%q,"decimals":18,"symbol":"DAI"}]`, evmTokenA, evmTokenB)))

	assertJSONEq(t, fmt.Sprintf(`{
		"native":{"raw":"1000000000000000000","decimals":18,"symbol":"ETH"},
		"tokens":[
			{"contract":%q,"raw":"1000000","decimals":6,"symbol":"USDT"},
			{"contract":%q,"raw":"0","decimals":18,"symbol":"DAI"}
		]}`, evmTokenA, evmTokenB), result(t, resp))

	// Token calls run with bounded concurrency, so the last completed request is
	// intentionally nondeterministic. It must still be balanceOf(holder)
	// against one of the requested contracts.
	params := node.params("eth_call")
	var call struct{ To, Data string }
	_ = json.Unmarshal(params[0], &call)
	wantData := "0x70a08231" + strings.Repeat("0", 24) + strings.TrimPrefix(evmSelf, "0x")
	if call.Data != wantData {
		t.Fatalf("balanceOf calldata = %s, want %s", call.Data, wantData)
	}
	to := strings.ToLower(call.To)
	if to != evmTokenA && to != evmTokenB {
		t.Fatalf("eth_call to = %s, want one of %s / %s", call.To, evmTokenA, evmTokenB)
	}
}

func TestEVMBalancesNoTokens(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getBalance", "0x0")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })
	resp := e.rpc("kt_getBalances", balancesParams("eth", evmSelf, ""))
	assertJSONEq(t, `{"native":{"raw":"0","decimals":18,"symbol":"ETH"},"tokens":[]}`, result(t, resp))
}

func TestPortfolioCombinesChainsAndIsolatesFailures(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getBalance", "0x5")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.PolygonURLs = []string{node.srv.URL}
	})
	params := fmt.Sprintf(`{"accounts":[
		{"chain":"eth","address":%q},
		{"chain":"polygon","address":%q},
		{"chain":"solana","address":"not-a-solana-address"}
	]}`, evmSelf, evmSelf)
	accounts := result(t, e.rpc("kt_getPortfolio", params))["accounts"].([]any)
	if len(accounts) != 3 {
		t.Fatalf("accounts length = %d, want 3", len(accounts))
	}
	eth := accounts[0].(map[string]any)
	polygon := accounts[1].(map[string]any)
	bad := accounts[2].(map[string]any)
	if eth["result"].(map[string]any)["native"].(map[string]any)["symbol"] != "ETH" {
		t.Fatalf("bad eth result: %v", eth)
	}
	if polygon["result"].(map[string]any)["native"].(map[string]any)["symbol"] != "POL" {
		t.Fatalf("bad polygon result: %v", polygon)
	}
	if bad["error"] == nil || bad["result"] != nil {
		t.Fatalf("invalid sibling must be isolated: %v", bad)
	}
}

func TestPolygonNativeSymbol(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getBalance", "0x5")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.PolygonURLs = []string{node.srv.URL} })
	resp := e.rpc("kt_getBalances", balancesParams("polygon", evmSelf, ""))
	assertJSONEq(t, `{"native":{"raw":"5","decimals":18,"symbol":"POL"},"tokens":[]}`, result(t, resp))
}

func TestBNBBalancesUseDedicatedChain(t *testing.T) {
	node := newRPCFake(t)
	scriptEVMBalances(node, map[string]string{
		"0xe9e7cea3dedca5984780bafc599bd69add087d56": "0x64",
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.BNBURLs = []string{node.srv.URL} })
	resp := e.rpc("kt_getBalances", balancesParams("bnb", evmSelf,
		`[{"contract":"0xe9e7cea3dedca5984780bafc599bd69add087d56","decimals":18,"symbol":"BUSD"}]`))
	assertJSONEq(t, `{
		"native":{"raw":"1000000000000000000","decimals":18,"symbol":"BNB"},
		"tokens":[{"contract":"0xe9e7cea3dedca5984780bafc599bd69add087d56","raw":"100","decimals":18,"symbol":"BUSD"}]
	}`, result(t, resp))
}

func TestEVMPerTokenErrorIsolation(t *testing.T) {
	node := newRPCFake(t)
	// Token A resolves; token B (not scripted) reverts.
	scriptEVMBalances(node, map[string]string{
		evmTokenA: "0x0000000000000000000000000000000000000000000000000000000000000064", // 100
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_getBalances", balancesParams("eth", evmSelf,
		fmt.Sprintf(`[{"contract":%q,"decimals":6,"symbol":"OK"},{"contract":%q,"decimals":18,"symbol":"BAD"}]`, evmTokenA, evmTokenB)))
	res := result(t, resp)

	tokens := res["tokens"].([]any)
	good := tokens[0].(map[string]any)
	bad := tokens[1].(map[string]any)
	if good["raw"] != "100" || good["error"] != nil {
		t.Fatalf("healthy token corrupted by sibling failure: %v", good)
	}
	if bad["error"] != "token balance temporarily unavailable" {
		t.Fatalf("failing token must carry a privacy-safe availability error: %v", bad)
	}
	if bad["raw"] != "0" {
		t.Fatalf("failing token raw should be \"0\": %v", bad)
	}
	if res["native"].(map[string]any)["raw"] != "1000000000000000000" {
		t.Fatal("native balance must be unaffected by token errors")
	}
}

func TestEVMBalancesNativeFailureFailsCall(t *testing.T) {
	node := newRPCFake(t)
	node.nodeError("eth_getBalance", -32000, "header not found")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })
	resp := e.rpc("kt_getBalances", balancesParams("eth", evmSelf, ""))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	if d := errData(t, errObj); d["message"] != "upstream rejected request" {
		t.Fatalf("untrusted node message must be normalized: %v", d)
	}
}

func TestTronBalances(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON("/v1/accounts/"+tronSelfB58, fmt.Sprintf(
		`{"data":[{"address":%q,"balance":5000000,"trc20":[{%q:"123456"}]}],"success":true}`,
		tronSelfHex, tronUSDT))
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	resp := e.rpc("kt_getBalances", balancesParams("tron", tronSelfB58,
		fmt.Sprintf(`[{"contract":%q,"decimals":6,"symbol":"USDT"},{"contract":"TVj7RNVHy6thbM7BWdSe9G6gXwKhjhdNaS","decimals":18,"symbol":"JST"}]`, tronUSDT)))

	assertJSONEq(t, fmt.Sprintf(`{
		"native":{"raw":"5000000","decimals":6,"symbol":"TRX"},
		"tokens":[
			{"contract":%q,"raw":"123456","decimals":6,"symbol":"USDT"},
			{"contract":"TVj7RNVHy6thbM7BWdSe9G6gXwKhjhdNaS","raw":"0","decimals":18,"symbol":"JST"}
		]}`, tronUSDT), result(t, resp))
}

func TestTronMalformedNativeBalanceFailsCallInsteadOfBecomingZero(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON("/v1/accounts/"+tronSelfB58, fmt.Sprintf(
		`{"data":[{"address":%q,"balance":"not-a-balance"}],"success":true}`,
		tronSelfHex))
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	resp := e.rpc("kt_getBalances", balancesParams("tron", tronSelfB58, ""))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	data := errData(t, errObj)
	if data["upstream"] != "trongrid" || data["message"] != "upstream temporarily unavailable" {
		t.Fatalf("malformed account data must remain a privacy-safe upstream failure: %v", data)
	}
}

func TestTronBalancesUnknownAccount(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON("/v1/accounts/", `{"data":[],"success":true}`)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })
	resp := e.rpc("kt_getBalances", balancesParams("tron", tronSelfB58, ""))
	assertJSONEq(t, `{"native":{"raw":"0","decimals":6,"symbol":"TRX"},"tokens":[]}`, result(t, resp))
}

func TestSolanaBalances(t *testing.T) {
	node := newRPCFake(t)
	node.result("getBalance", map[string]any{"context": map[string]any{"slot": 1}, "value": 2039280})
	node.result("getTokenAccountsByOwner", map[string]any{
		"context": map[string]any{"slot": 1},
		"value": []any{
			map[string]any{"account": map[string]any{"data": map[string]any{"parsed": map[string]any{"info": map[string]any{"tokenAmount": map[string]any{"amount": "1200000"}}}}}},
			map[string]any{"account": map[string]any{"data": map[string]any{"parsed": map[string]any{"info": map[string]any{"tokenAmount": map[string]any{"amount": "300000"}}}}}},
		},
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.SolanaURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_getBalances", balancesParams("solana", solSelf,
		`[{"contract":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","decimals":6,"symbol":"USDC"}]`))

	assertJSONEq(t, `{
		"native":{"raw":"2039280","decimals":9,"symbol":"SOL"},
		"tokens":[{"contract":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","raw":"1500000","decimals":6,"symbol":"USDC"}]
	}`, result(t, resp))
	params := node.params("getTokenAccountsByOwner")
	var filter map[string]string
	if err := json.Unmarshal(params[1], &filter); err != nil {
		t.Fatal(err)
	}
	if filter["mint"] != "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" {
		t.Fatalf("wrong mint filter: %v", filter)
	}
}

func TestBalancesCacheHitAndKeying(t *testing.T) {
	node := newRPCFake(t)
	scriptEVMBalances(node, map[string]string{evmTokenA: "0x1"})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	tokensA := fmt.Sprintf(`[{"contract":%q,"decimals":6,"symbol":"A"}]`, evmTokenA)
	p := balancesParams("eth", evmSelf, tokensA)

	result(t, e.rpc("kt_getBalances", p))
	result(t, e.rpc("kt_getBalances", p)) // within 10s TTL: served from cache
	if got := node.count("eth_getBalance"); got != 1 {
		t.Fatalf("expected 1 upstream native call across 2 identical requests, got %d", got)
	}

	// Different tokenset -> different cache key -> upstream hit.
	result(t, e.rpc("kt_getBalances", balancesParams("eth", evmSelf, "")))
	if got := node.count("eth_getBalance"); got != 2 {
		t.Fatalf("different tokenset must miss the cache, native calls = %d", got)
	}

	// TTL expiry -> refetch.
	e.clk.Advance(11 * time.Second)
	result(t, e.rpc("kt_getBalances", p))
	if got := node.count("eth_getBalance"); got != 3 {
		t.Fatalf("expected refetch after 10s TTL, native calls = %d", got)
	}
}

func TestBalancesInvalidParams(t *testing.T) {
	node := newRPCFake(t) // must never be called
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	cases := []struct {
		name   string
		params string
	}{
		{"missing params", `null`},
		{"bad chain", `{"chain":"dogecoin","address":"0x1111111111111111111111111111111111111111"}`},
		{"missing address", `{"chain":"eth"}`},
		{"blank address", `{"chain":"eth","address":"   "}`},
		{"bad evm address", `{"chain":"eth","address":"not-an-address"}`},
		{"short evm address", `{"chain":"eth","address":"0x1234"}`},
		{"blank token contract", `{"chain":"eth","address":"0x1111111111111111111111111111111111111111","tokens":[{"contract":"","decimals":6,"symbol":"X"}]}`},
		{"wrong params type", `[1,2,3]`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resp := e.rpc("kt_getBalances", tc.params)
			errObj := assertErrCode(t, resp, rpc.CodeInvalidParams)
			if errObj["message"] == "" {
				t.Fatal("invalid-params error must explain which field is wrong")
			}
		})
	}
	if node.totalCalls() != 0 {
		t.Fatalf("invalid params must never reach an upstream, saw %d calls", node.totalCalls())
	}
}

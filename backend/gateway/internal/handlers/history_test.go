package handlers_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

// tronGridFixture wires realistic TronGrid shapes: TRC-20 transfers
// (transaction_id/from/to/value/token_info) plus native transactions
// (txID/ret.contractRet/raw_data TransferContract).
func tronGridFixture(t *testing.T) *restFake {
	grid := newRESTFake(t)
	grid.routeJSON("/v1/accounts/"+tronSelfB58+"/transactions/trc20", fmt.Sprintf(`{
		"data": [
			{"transaction_id":"t1","from":%q,"to":%q,"value":"1000000","block_timestamp":5000,
			 "token_info":{"symbol":"USDT","decimals":6,"address":%q}},
			{"transaction_id":"tdup","from":%q,"to":%q,"value":"250000","block_timestamp":3000,
			 "token_info":{"symbol":"USDT","decimals":6,"address":%q}}
		],
		"success": true
	}`, tronSelfB58, tronOtherB58, tronUSDT, tronOtherB58, tronSelfB58, tronUSDT))
	grid.routeJSON("/v1/accounts/"+tronSelfB58+"/transactions", fmt.Sprintf(`{
		"data": [
			{"txID":"n1","block_timestamp":4000,"ret":[{"contractRet":"SUCCESS"}],
			 "raw_data":{"contract":[{"type":"TransferContract",
				"parameter":{"value":{"amount":7000000,"owner_address":%q,"to_address":%q}}}]}},
			{"txID":"tdup","block_timestamp":3000,"ret":[{"contractRet":"SUCCESS"}],
			 "raw_data":{"contract":[{"type":"TransferContract",
				"parameter":{"value":{"amount":250000,"owner_address":%q,"to_address":%q}}}]}},
			{"txID":"n3","block_timestamp":2000,"ret":[{"contractRet":"REVERT"}],
			 "raw_data":{"contract":[{"type":"TransferContract",
				"parameter":{"value":{"amount":42,"owner_address":%q,"to_address":%q}}}]}},
			{"txID":"n4","block_timestamp":1000,"ret":[{"contractRet":"SUCCESS"}],
			 "raw_data":{"contract":[{"type":"TriggerSmartContract",
				"parameter":{"value":{"owner_address":%q}}}]}}
		],
		"success": true
	}`, tronOtherHex, tronSelfHex, tronOtherHex, tronSelfHex, tronSelfHex, tronOtherHex, tronSelfHex))
	return grid
}

// Note the route registration above: the trc20 route is a longer prefix of
// the same /transactions path, so prefix matching keeps them distinct.

func TestTronHistoryMergeDedupeDirection(t *testing.T) {
	grid := tronGridFixture(t)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"tron","address":%q}`, tronSelfB58)))
	if res["status"] != "ok" {
		t.Fatalf("tron history must always be supported, got %v", res["status"])
	}
	assertJSONEq(t, `[
		{"hash":"t1","direction":"out","amountRaw":"1000000","decimals":6,"symbol":"USDT","timestampMs":5000,"status":"ok"},
		{"hash":"n1","direction":"in","amountRaw":"7000000","decimals":6,"symbol":"TRX","timestampMs":4000,"status":"ok"},
		{"hash":"tdup","direction":"in","amountRaw":"250000","decimals":6,"symbol":"USDT","timestampMs":3000,"status":"ok"},
		{"hash":"n3","direction":"out","amountRaw":"42","decimals":6,"symbol":"TRX","timestampMs":2000,"status":"failed"}
	]`, res["records"])
	// n4 (TriggerSmartContract) skipped; tdup deduped across the two feeds.
}

func TestTronHistoryLimit(t *testing.T) {
	grid := tronGridFixture(t)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"tron","address":%q,"limit":2}`, tronSelfB58)))
	records := res["records"].([]any)
	if len(records) != 2 {
		t.Fatalf("limit 2 must cap the merged list, got %d records", len(records))
	}
	if records[0].(map[string]any)["hash"] != "t1" || records[1].(map[string]any)["hash"] != "n1" {
		t.Fatalf("records must be newest-first: %v", records)
	}
}

func TestTronHistoryUpstreamFailure(t *testing.T) {
	grid := newRESTFake(t)
	grid.route("/v1/accounts/", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(502) })
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	resp := e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"tron","address":%q}`, tronSelfB58))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	d := errData(t, errObj)
	if d["message"] == "" || d["upstream"] == "" {
		t.Fatalf("-32000 must carry upstream and message: %v", d)
	}
}

func TestEthHistoryWithoutKeyUnsupported(t *testing.T) {
	scan := newRESTFake(t) // must not be called
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EtherscanURL = scan.srv.URL })

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	assertJSONEq(t, `{"status":"unsupported","records":[]}`, res)
	if len(scan.hitsFor("/")) != 0 {
		t.Fatal("without ETHERSCAN_API_KEY no upstream call may happen")
	}
}

func TestEthHistoryWithKey(t *testing.T) {
	scan := newRESTFake(t)
	scan.routeJSON("/", fmt.Sprintf(`{
		"status":"1","message":"OK",
		"result":[
			{"hash":"0xh1","from":%q,"to":"0x2222222222222222222222222222222222222222","value":"1000","timeStamp":"1700000100","isError":"0"},
			{"hash":"0xh2","from":"0x2222222222222222222222222222222222222222","to":%q,"value":"2000","timeStamp":"1700000000","isError":"1"}
		]}`, evmSelf, evmSelf))
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "test-key"
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q,"limit":10}`, evmSelf)))
	if res["status"] != "ok" {
		t.Fatalf("status = %v", res["status"])
	}
	assertJSONEq(t, `[
		{"hash":"0xh1","direction":"out","amountRaw":"1000","decimals":18,"symbol":"ETH","timestampMs":1700000100000,"status":"ok"},
		{"hash":"0xh2","direction":"in","amountRaw":"2000","decimals":18,"symbol":"ETH","timestampMs":1700000000000,"status":"failed"}
	]`, res["records"])

	hits := scan.hitsFor("/")
	if len(hits) != 1 {
		t.Fatalf("expected 1 Etherscan call, got %d", len(hits))
	}
	u, _ := url.Parse(hits[0].Path)
	q := u.Query()
	for k, want := range map[string]string{
		"chainid": "1", "module": "account", "action": "txlist",
		"address": evmSelf, "apikey": "test-key", "sort": "desc", "offset": "10",
	} {
		if q.Get(k) != want {
			t.Fatalf("etherscan query %s = %q, want %q (full: %s)", k, q.Get(k), want, hits[0].Path)
		}
	}
}

func TestPolygonHistoryUsesChainID137(t *testing.T) {
	scan := newRESTFake(t)
	scan.routeJSON("/", `{"status":"1","message":"OK","result":[]}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "k"
	})
	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"polygon","address":%q}`, evmSelf)))
	if res["status"] != "ok" {
		t.Fatalf("status = %v", res["status"])
	}
	u, _ := url.Parse(scan.hitsFor("/")[0].Path)
	if u.Query().Get("chainid") != "137" {
		t.Fatalf("polygon must query chainid=137, got %q", u.Query().Get("chainid"))
	}
}

func TestEthHistoryEtherscanErrorSurfaces(t *testing.T) {
	scan := newRESTFake(t)
	scan.routeJSON("/", `{"status":"0","message":"NOTOK","result":"Max rate limit reached"}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "k"
	})
	resp := e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	if d := errData(t, errObj); d["message"] != "Max rate limit reached" {
		t.Fatalf("Etherscan error text must surface, got %v", d)
	}
}

func TestSolanaHistoryWithoutKeyUnsupported(t *testing.T) {
	e := newEnv(t, nil)
	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"solana","address":%q}`, solSelf)))
	assertJSONEq(t, `{"status":"unsupported","records":[]}`, res)
}

func TestSolanaHistoryWithHeliusKey(t *testing.T) {
	hel := newRESTFake(t)
	hel.routeJSON("/v0/addresses/"+solSelf+"/transactions", fmt.Sprintf(`[
		{"signature":"sig1","timestamp":1700000200,"transactionError":null,
		 "nativeTransfers":[{"fromUserAccount":%q,"toUserAccount":%q,"amount":5000000}]},
		{"signature":"sig2","timestamp":1700000100,"transactionError":{"InstructionError":[0,"Custom"]},
		 "nativeTransfers":[{"fromUserAccount":%q,"toUserAccount":%q,"amount":123}]},
		{"signature":"sig3","timestamp":1700000050,"transactionError":null,"nativeTransfers":[]}
	]`, solSelf, solOther, solOther, solSelf))
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.HeliusURL = hel.srv.URL
		cfg.HeliusKey = "helius-key"
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"solana","address":%q}`, solSelf)))
	if res["status"] != "ok" {
		t.Fatalf("status = %v", res["status"])
	}
	assertJSONEq(t, `[
		{"hash":"sig1","direction":"out","amountRaw":"5000000","decimals":9,"symbol":"SOL","timestampMs":1700000200000,"status":"ok"},
		{"hash":"sig2","direction":"in","amountRaw":"123","decimals":9,"symbol":"SOL","timestampMs":1700000100000,"status":"failed"}
	]`, res["records"])

	u, _ := url.Parse(hel.hitsFor("/v0/addresses/")[0].Path)
	if u.Query().Get("api-key") != "helius-key" {
		t.Fatal("Helius api-key must be attached by the gateway")
	}
}

func TestHistoryInvalidParams(t *testing.T) {
	e := newEnv(t, nil)
	for _, params := range []string{
		`{"chain":"tron"}`,              // missing address
		`{"chain":"tron","address":""}`, // blank address
		`{"chain":"btc","address":"x"}`, // bad chain
		fmt.Sprintf(`{"chain":"tron","address":%q,"limit":0}`, tronSelfB58),   // zero limit
		fmt.Sprintf(`{"chain":"tron","address":%q,"limit":-5}`, tronSelfB58),  // negative limit
		fmt.Sprintf(`{"chain":"tron","address":%q,"limit":"x"}`, tronSelfB58), // non-numeric limit
	} {
		assertErrCode(t, e.rpc("kt_getHistory", params), rpc.CodeInvalidParams)
	}
}

func TestHistoryCache(t *testing.T) {
	grid := tronGridFixture(t)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	p := fmt.Sprintf(`{"chain":"tron","address":%q}`, tronSelfB58)
	result(t, e.rpc("kt_getHistory", p))
	result(t, e.rpc("kt_getHistory", p))
	if got := grid.hitCount("/v1/accounts/"); got != 2 { // trc20 + native, once each
		t.Fatalf("second call within 30s TTL must be cached, upstream hits = %d", got)
	}
	e.clk.Advance(31 * time.Second)
	result(t, e.rpc("kt_getHistory", p))
	if got := grid.hitCount("/v1/accounts/"); got != 4 {
		t.Fatalf("expected refetch after TTL, upstream hits = %d", got)
	}
	// A different limit is a different cache key.
	result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"tron","address":%q,"limit":3}`, tronSelfB58)))
	if got := grid.hitCount("/v1/accounts/"); got != 6 {
		t.Fatalf("different limit must miss the cache, upstream hits = %d", got)
	}
}

// Guard: the fixture endpoints must be distinguishable by prefix matching.
func TestTronFixtureRoutesDistinct(t *testing.T) {
	grid := tronGridFixture(t)
	resp, err := http.Get(grid.srv.URL + "/v1/accounts/" + tronSelfB58 + "/transactions/trc20?limit=5")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out struct {
		Data []map[string]any `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	if len(out.Data) == 0 || out.Data[0]["transaction_id"] != "t1" {
		t.Fatalf("trc20 route not matched correctly: %v", out.Data)
	}
}

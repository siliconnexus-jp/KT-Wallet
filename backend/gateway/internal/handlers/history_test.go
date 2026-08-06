package handlers_test

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

func tronTRC20FixtureID(txID, contract, from, to, value string) string {
	semantic := strings.Join([]string{strings.ToLower(txID), contract, from, to, value}, "\x00")
	digest := sha256.Sum256([]byte(semantic))
	return fmt.Sprintf("%s:trc20:%s:%x", txID, contract, digest[:8])
}

// tronGridFixture wires realistic TronGrid shapes: TRC-20 transfers
// (transaction_id/from/to/value/token_info) plus native transactions
// (txID/ret.contractRet/raw_data TransferContract).
func tronGridFixture(t *testing.T) *restFake {
	grid := newRESTFake(t)
	grid.routeJSON("/v1/accounts/"+tronSelfB58+"/transactions/trc20", fmt.Sprintf(`{
		"data": [
			{"transaction_id":%q,"from":%q,"to":%q,"type":"Transfer","value":"1000000","block_timestamp":5000,
			 "token_info":{"symbol":"USDT","decimals":6,"address":%q}},
			{"transaction_id":%q,"from":%q,"to":%q,"type":"Transfer","value":"250000","block_timestamp":3000,
			 "token_info":{"symbol":"USDT","decimals":6,"address":%q}}
		],
		"success": true
	}`, tronTx1, tronSelfB58, tronOtherB58, tronUSDT, tronTx2, tronOtherB58, tronSelfB58, tronUSDT))
	grid.routeJSON("/v1/accounts/"+tronSelfB58+"/transactions", fmt.Sprintf(`{
		"data": [
			{"txID":%q,"block_timestamp":4000,"ret":[{"contractRet":"SUCCESS"}],
			 "raw_data":{"contract":[{"type":"TransferContract",
				"parameter":{"value":{"amount":7000000,"owner_address":%q,"to_address":%q}}}]}},
			{"txID":%q,"block_timestamp":3000,"ret":[{"contractRet":"SUCCESS"}],
			 "raw_data":{"contract":[{"type":"TransferContract",
				"parameter":{"value":{"amount":250000,"owner_address":%q,"to_address":%q}}}]}},
			{"txID":%q,"block_timestamp":2000,"ret":[{"contractRet":"REVERT"}],
			 "raw_data":{"contract":[{"type":"TransferContract",
				"parameter":{"value":{"amount":42,"owner_address":%q,"to_address":%q}}}]}},
			{"txID":%q,"block_timestamp":1000,"ret":[{"contractRet":"SUCCESS"}],
			 "raw_data":{"contract":[{"type":"TriggerSmartContract",
				"parameter":{"value":{"owner_address":%q}}}]}}
		],
		"success": true
	}`, tronTx3, tronOtherHex, tronSelfHex, tronTx2, tronOtherHex, tronSelfHex,
		tronTx4, tronSelfHex, tronOtherHex, tronTx5, tronSelfHex))
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/internal-transactions",
		`{"data":[],"success":true}`,
	)
	return grid
}

// Note the route registration above: the trc20 route is a longer prefix of
// the same /transactions path, so prefix matching keeps them distinct.

func TestTronHistoryMergeDedupeDirection(t *testing.T) {
	grid := tronGridFixture(t)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"tron","address":%q}`, tronSelfB58)))
	if res["chain"] != "tron" || res["network"] != "tron-mainnet" || res["address"] != tronSelfB58 {
		t.Fatalf("history response must bind exact request identity: %v", res)
	}
	if res["status"] != "ok" {
		t.Fatalf("tron history must always be supported, got %v", res["status"])
	}
	assertJSONEq(t, fmt.Sprintf(`[
		{"id":"%[5]s","hash":"%[1]s","direction":"out","from":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","to":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","amountRaw":"1000000","decimals":6,"symbol":"USDT","contract":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","verified":true,"timestampMs":5000,"status":"ok"},
		{"id":"%[2]s","hash":"%[2]s","direction":"in","from":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","to":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","amountRaw":"7000000","decimals":6,"symbol":"TRX","verified":true,"timestampMs":4000,"status":"ok"},
		{"id":"%[6]s","hash":"%[3]s","direction":"in","from":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","to":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","amountRaw":"250000","decimals":6,"symbol":"USDT","contract":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","verified":true,"timestampMs":3000,"status":"ok"},
		{"id":"%[3]s","hash":"%[3]s","direction":"in","from":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","to":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","amountRaw":"250000","decimals":6,"symbol":"TRX","verified":true,"timestampMs":3000,"status":"ok"},
		{"id":"%[4]s","hash":"%[4]s","direction":"out","from":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","to":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","amountRaw":"42","decimals":6,"symbol":"TRX","verified":true,"timestampMs":2000,"status":"failed"}
	]`, tronTx1, tronTx3, tronTx2, tronTx4,
		tronTRC20FixtureID(tronTx1, tronUSDT, tronSelfB58, tronOtherB58, "1000000"),
		tronTRC20FixtureID(tronTx2, tronUSDT, tronOtherB58, tronSelfB58, "250000")), res["records"])
	// TriggerSmartContract is skipped. A real TRX movement sharing a hash with
	// a TRC-20 event is retained because it is a distinct asset movement.
}

func TestTronHistoryLimit(t *testing.T) {
	grid := tronGridFixture(t)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"tron","address":%q,"limit":2}`, tronSelfB58)))
	records := res["records"].([]any)
	if len(records) != 2 {
		t.Fatalf("limit 2 must cap the merged list, got %d records", len(records))
	}
	if records[0].(map[string]any)["hash"] != tronTx1 || records[1].(map[string]any)["hash"] != tronTx3 {
		t.Fatalf("records must be newest-first: %v", records)
	}
}

func TestTronHistoryFiltersUnrelatedRowsAndPreservesContractEvents(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/transactions/trc20",
		fmt.Sprintf(`{"data":[
			{"transaction_id":%q,"from":%q,"to":%q,"type":"Transfer","value":"1",`+
			`"block_timestamp":5000,"token_info":{"symbol":"USDT","decimals":6,"address":%q}},
			{"transaction_id":%q,"from":%q,"to":%q,"type":"Transfer","value":"2",`+
			`"block_timestamp":4000,"token_info":{"symbol":"USDT","decimals":6,"address":%q}}
		],"success":true}`,
			tronTx1, tronOtherB58, "TJmmqjb1DK9TTZbQXzRQ2AuA94z4gKAPFh", tronUSDT,
			tronTx2, tronOtherB58, tronSelfB58, tronUSDT),
	)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/transactions",
		fmt.Sprintf(`{"data":[{"txID":%q,"block_timestamp":3000,"ret":[{"contractRet":"SUCCESS"}],`+
			`"raw_data":{"contract":[
				{"type":"TransferContract","parameter":{"value":{"amount":3,"owner_address":%q,"to_address":%q}}},
				{"type":"TransferContract","parameter":{"value":{"amount":4,"owner_address":%q,"to_address":%q}}}
			]}}],"success":true}`,
			tronTx3, tronOtherHex, "41608f8da72479edc7dd921e4c30bb7e7cddbe722e", tronSelfHex, tronOtherHex),
	)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/internal-transactions",
		fmt.Sprintf(`{"data":[{"tx_id":%q,"internal_tx_id":%q,"from_address":%q,"to_address":%q,`+
			`"block_timestamp":2000,"data":{"rejected":false,"call_value":{"_":5}}}],"success":true}`,
			tronTx4, tronTrace1, tronOtherHex, "41608f8da72479edc7dd921e4c30bb7e7cddbe722e"),
	)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"tron","address":%q}`, tronSelfB58)))
	assertJSONEq(t, fmt.Sprintf(`[
		{"id":"%[3]s","hash":"%[1]s","direction":"in","from":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","to":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","amountRaw":"2","decimals":6,"symbol":"USDT","contract":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","verified":true,"timestampMs":4000,"status":"ok"},
		{"id":"%[2]s:contract:1","hash":"%[2]s","direction":"out","from":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","to":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","amountRaw":"4","decimals":6,"symbol":"TRX","verified":true,"timestampMs":3000,"status":"ok"}
	]`, tronTx2, tronTx3,
		tronTRC20FixtureID(tronTx2, tronUSDT, tronOtherB58, tronSelfB58, "2")), res["records"])
}

func TestTronHistoryIncludesTRC10AndInternalTRX(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/transactions/trc20",
		`{"data":[],"success":true}`,
	)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/internal-transactions",
		fmt.Sprintf(`{"data":[{
			"tx_id":%q,"internal_tx_id":%q,
			"from_address":%q,"to_address":%q,"block_timestamp":3000,
			"data":{"rejected":false,"call_value":{"_":2500000}}
		}],"success":true}`, tronTx1, tronTrace1, tronOtherHex, tronSelfHex),
	)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/transactions",
		fmt.Sprintf(`{"data":[{
			"txID":%q,"block_timestamp":2000,
			"ret":[{"contractRet":"SUCCESS"}],
			"raw_data":{"contract":[{"type":"TransferAssetContract",
				"parameter":{"value":{"amount":42,"asset_name":"1002000",
					"owner_address":%q,"to_address":%q}}}]}
		}],"success":true}`, tronTx2, tronSelfHex, tronOtherHex),
	)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	res := result(t, e.rpc("kt_getHistory",
		fmt.Sprintf(`{"chain":"tron","address":%q}`, tronSelfB58)))
	assertJSONEq(t, fmt.Sprintf(`[
		{"id":"%[1]s:internal:%[2]s","hash":"%[1]s","direction":"in","from":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","to":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","amountRaw":"2500000","decimals":6,"symbol":"TRX","verified":true,"timestampMs":3000,"status":"ok"},
		{"id":"%[3]s:trc10:1002000","hash":"%[3]s","direction":"out","from":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","to":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","amountRaw":"42","decimals":0,"symbol":"TRC10","contract":"1002000","verified":false,"timestampMs":2000,"status":"ok"}
	]`, tronTx1, tronTrace1, tronTx2), res["records"])
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

func TestEthHistoryWithoutKeyUsesPublicExplorer(t *testing.T) {
	explorer := newRESTFake(t)
	explorer.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("action") != "txlist" {
			_, _ = fmt.Fprint(w, `{"status":"1","message":"OK","result":[]}`)
			return
		}
		_, _ = fmt.Fprintf(w, `{
			"status":"1","message":"OK",
			"result":[
				{"hash":"0x1111111111111111111111111111111111111111111111111111111111111111","from":%q,"to":"0x2222222222222222222222222222222222222222","value":"77","timeStamp":"1700000300","isError":"0"}
			]}`, evmSelf)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EVMHistoryFallbackURLs = map[string]string{
			"eth-mainnet": explorer.srv.URL,
		}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	if res["status"] != "ok" {
		t.Fatalf("status = %v", res["status"])
	}
	assertJSONEq(t, `[
		{"id":"0x1111111111111111111111111111111111111111111111111111111111111111","hash":"0x1111111111111111111111111111111111111111111111111111111111111111","direction":"out","from":"0x1111111111111111111111111111111111111111","to":"0x2222222222222222222222222222222222222222","amountRaw":"77","decimals":18,"symbol":"ETH","verified":true,"timestampMs":1700000300000,"status":"ok"}
	]`, res["records"])
	if explorer.hitCount("/") != 3 {
		t.Fatal("keyless history must use the configured public explorer")
	}
}

func TestEVMHistoryMissingOrContradictoryExecutionEvidenceIsUnknown(t *testing.T) {
	explorer := newRESTFake(t)
	explorer.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("action") != "txlist" {
			_, _ = w.Write([]byte(`{"status":"1","message":"OK","result":[]}`))
			return
		}
		_, _ = fmt.Fprintf(w, `{"status":"1","message":"OK","result":[
			{"hash":"0x2222222222222222222222222222222222222222222222222222222222222222","from":%q,"to":"0x2222222222222222222222222222222222222222","value":"1","timeStamp":"1700000600"},
			{"hash":"0x3333333333333333333333333333333333333333333333333333333333333333","from":%q,"to":"0x3333333333333333333333333333333333333333","value":"2","timeStamp":"1700000500","isError":"0","txreceipt_status":"0"}
		]}`, evmSelf, evmSelf)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EVMHistoryFallbackURLs = map[string]string{
			"eth-mainnet": explorer.srv.URL,
		}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	assertJSONEq(t, `[
		{"id":"0x2222222222222222222222222222222222222222222222222222222222222222","hash":"0x2222222222222222222222222222222222222222222222222222222222222222","direction":"out","from":"0x1111111111111111111111111111111111111111","to":"0x2222222222222222222222222222222222222222","amountRaw":"1","decimals":18,"symbol":"ETH","verified":true,"timestampMs":1700000600000,"status":"unknown"},
		{"id":"0x3333333333333333333333333333333333333333333333333333333333333333","hash":"0x3333333333333333333333333333333333333333333333333333333333333333","direction":"out","from":"0x1111111111111111111111111111111111111111","to":"0x3333333333333333333333333333333333333333","amountRaw":"2","decimals":18,"symbol":"ETH","verified":true,"timestampMs":1700000500000,"status":"unknown"}
	]`, res["records"])
}

func TestEVMHistoryAcceptsOfficialIndexedTokenEvidence(t *testing.T) {
	explorer := newRESTFake(t)
	explorer.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("action") != "tokentx" {
			_, _ = w.Write([]byte(`{"status":"1","message":"OK","result":[]}`))
			return
		}
		_, _ = fmt.Fprintf(w, `{"status":"1","message":"OK","result":[{
			"hash":"0x4444444444444444444444444444444444444444444444444444444444444444","from":%q,"to":"0x2222222222222222222222222222222222222222",
			"value":"2500000","timeStamp":"1700000100","tokenDecimal":"6",
			"tokenSymbol":"USDT","contractAddress":"0xdAC17F958D2ee523a2206206994597C13D831ec7",
			"blockNumber":"4730207","blockHash":"0x022c5e6a3d2487a8ccf8946a2ffb74938bf8e5c8a3f6d91b41c56378a96b5c37",
			"transactionIndex":"81","confirmations":"1"
		}]}`, evmSelf)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EVMHistoryFallbackURLs = map[string]string{"eth-mainnet": explorer.srv.URL}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	records := res["records"].([]any)
	if len(records) != 1 || records[0].(map[string]any)["status"] != "ok" {
		t.Fatalf("canonical indexed token event must be confirmed: %v", records)
	}
}

func TestEVMHistoryAcceptsBlockscoutInternalKeys(t *testing.T) {
	explorer := newRESTFake(t)
	explorer.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("action") != "txlistinternal" {
			_, _ = w.Write([]byte(`{"status":"1","message":"OK","result":[]}`))
			return
		}
		_, _ = fmt.Fprintf(w, `{"status":"1","message":"OK","result":[{
			"transactionHash":"0x5555555555555555555555555555555555555555555555555555555555555555","index":"0_1","from":"0x2222222222222222222222222222222222222222",
			"to":%q,"value":"5000000000000000","timeStamp":"1700000100","isError":"0"
		}]}`, evmSelf)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EVMHistoryFallbackURLs = map[string]string{"eth-mainnet": explorer.srv.URL}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	assertJSONEq(t, `[{"id":"0x5555555555555555555555555555555555555555555555555555555555555555:internal:0_1","hash":"0x5555555555555555555555555555555555555555555555555555555555555555","direction":"in",
		"from":"0x2222222222222222222222222222222222222222","to":"0x1111111111111111111111111111111111111111",
		"amountRaw":"5000000000000000","decimals":18,"symbol":"ETH","verified":true,
		"timestampMs":1700000100000,"status":"ok"}]`, res["records"])
}

func TestEVMHistoryOmitsExplorerRowsUnrelatedToWallet(t *testing.T) {
	explorer := newRESTFake(t)
	explorer.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Query().Get("action") {
		case "txlist":
			_, _ = fmt.Fprint(w, `{"status":"1","message":"OK","result":[{
				"hash":"0xabababababababababababababababababababababababababababababababab",
				"from":"0x2222222222222222222222222222222222222222",
				"to":"0x3333333333333333333333333333333333333333",
				"value":"1","timeStamp":"1700000200","isError":"0"
			}]}`)
		case "tokentx":
			_, _ = fmt.Fprint(w, `{"status":"1","message":"OK","result":[{
				"blockNumber":"123","timeStamp":"1700000100",
				"hash":"0xcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
				"blockHash":"0xefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefef",
				"from":"0x2222222222222222222222222222222222222222",
				"to":"0x3333333333333333333333333333333333333333","value":"1",
				"tokenSymbol":"USDC","tokenDecimal":"6",
				"contractAddress":"0x4444444444444444444444444444444444444444",
				"transactionIndex":"0","confirmations":"1","logIndex":"0"
			}]}`)
		default:
			_, _ = fmt.Fprint(w, `{"status":"1","message":"OK","result":[]}`)
		}
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EVMHistoryFallbackURLs = map[string]string{"eth-mainnet": explorer.srv.URL}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	if res["status"] != "ok" {
		t.Fatalf("status = %v", res["status"])
	}
	if records := res["records"].([]any); len(records) != 0 {
		t.Fatalf("unrelated explorer rows must not enter wallet history: %v", records)
	}
}

func TestTronHistoryMissingExecutionEvidenceIsUnknown(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/transactions/trc20",
		`{"data":[],"success":true}`,
	)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/internal-transactions",
		fmt.Sprintf(`{"data":[{
			"tx_id":%q,"internal_tx_id":%q,
			"from_address":%q,"to_address":%q,"block_timestamp":3000,
			"data":{"call_value":{"_":1000000}}
		}],"success":true}`, tronTx1, tronTrace1, tronOtherHex, tronSelfHex),
	)
	grid.routeJSON(
		"/v1/accounts/"+tronSelfB58+"/transactions",
		fmt.Sprintf(`{"data":[{
			"txID":%q,"block_timestamp":2000,
			"raw_data":{"contract":[{"type":"TransferContract",
				"parameter":{"value":{"amount":42,"owner_address":%q,"to_address":%q}}}]}
		}],"success":true}`, tronTx2, tronSelfHex, tronOtherHex),
	)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	res := result(t, e.rpc("kt_getHistory",
		fmt.Sprintf(`{"chain":"tron","address":%q}`, tronSelfB58)))
	assertJSONEq(t, fmt.Sprintf(`[
		{"id":"%[1]s:internal:%[2]s","hash":"%[1]s","direction":"in","from":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","to":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","amountRaw":"1000000","decimals":6,"symbol":"TRX","verified":true,"timestampMs":3000,"status":"unknown"},
		{"id":"%[3]s","hash":"%[3]s","direction":"out","from":"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C","to":"TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT","amountRaw":"42","decimals":6,"symbol":"TRX","verified":true,"timestampMs":2000,"status":"unknown"}
	]`, tronTx1, tronTrace1, tronTx2), res["records"])
	for _, hit := range grid.hitsFor("/v1/accounts/") {
		u, err := url.Parse(hit.Path)
		if err != nil || u.Query().Get("only_confirmed") != "true" {
			t.Fatalf("history feed did not require confirmed rows: %q", hit.Path)
		}
	}
}

func TestPolygonAmoyHistoryWithoutKeyUnsupported(t *testing.T) {
	e := newEnv(t, nil)
	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(
		`{"chain":"polygon","network":"polygon-amoy","address":%q}`, evmSelf,
	)))
	assertJSONEq(t, fmt.Sprintf(
		`{"chain":"polygon","network":"polygon-amoy","address":%q,"status":"unsupported","records":[]}`,
		evmSelf,
	), res)
}

func TestBNBHistoryUsesAlchemyBeforeEtherscan(t *testing.T) {
	alchemy := newRESTFake(t)
	alchemy.route("/", func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Params []map[string]any `json:"params"`
		}
		_ = json.NewDecoder(r.Body).Decode(&request)
		w.Header().Set("Content-Type", "application/json")
		if request.Params[0]["toAddress"] != nil {
			_, _ = fmt.Fprintf(w, `{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
				"uniqueId":"0xbnbtoken:log:7","blockNum":"0x201","hash":"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
				"from":"0x2222222222222222222222222222222222222222","to":%q,
				"asset":"FAKE-BUSD","category":"erc20",
				"rawContract":{"value":"0x2625a0","address":"0xed24fc36d5ee211ea25a80239fb8c4cfd80f12ee","decimal":"0x12"},
				"metadata":{"blockTimestamp":"2026-07-29T01:02:03Z"}
			}]}}`, evmSelf)
			return
		}
		_, _ = fmt.Fprintf(w, `{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
			"uniqueId":"0xbnb:external","blockNum":"0x200","hash":"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
			"from":%q,"to":"0x2222222222222222222222222222222222222222",
			"asset":"BNB","category":"external",
			"rawContract":{"value":"0xde0b6b3a7640000","address":null,"decimal":"0x12"},
			"metadata":{"blockTimestamp":"2026-07-29T01:01:00Z"}
		}]}}`, evmSelf)
	})
	etherscan := newRESTFake(t)
	etherscan.routeJSON("/", `{"status":"1","message":"OK","result":[]}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.AlchemyKeys = []string{"server-only-key"}
		cfg.AlchemyURLs = map[string][]string{"bnb-testnet": {alchemy.srv.URL}}
		cfg.EtherscanKey = "fallback-key"
		cfg.EtherscanURL = etherscan.srv.URL
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(
		`{"chain":"bnb","network":"bnb-testnet","address":%q}`, evmSelf,
	)))
	assertJSONEq(t, `[
		{"id":"0xbnbtoken:log:7","hash":"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","direction":"in","from":"0x2222222222222222222222222222222222222222","to":"0x1111111111111111111111111111111111111111","amountRaw":"2500000","decimals":18,"symbol":"BUSD","contract":"0xed24fc36d5ee211ea25a80239fb8c4cfd80f12ee","verified":true,"timestampMs":1785286923000,"status":"ok"},
		{"id":"0xbnb:external","hash":"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","direction":"out","from":"0x1111111111111111111111111111111111111111","to":"0x2222222222222222222222222222222222222222","amountRaw":"1000000000000000000","decimals":18,"symbol":"BNB","verified":true,"timestampMs":1785286860000,"status":"ok"}
	]`, res["records"])
	if alchemy.hitCount("/") != 2 {
		t.Fatalf("Alchemy must query both directions, hits = %d", alchemy.hitCount("/"))
	}
	if etherscan.hitCount("/") != 0 {
		t.Fatalf("healthy Alchemy must avoid fallback, Etherscan hits = %d", etherscan.hitCount("/"))
	}
}

func TestAlchemyFailureFallsBackToEtherscan(t *testing.T) {
	alchemy := newRESTFake(t)
	alchemy.routeJSON("/", `{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"temporary outage"}}`)
	scan := newRESTFake(t)
	scan.routeJSON("/", `{"status":"1","message":"OK","result":[]}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.AlchemyKeys = []string{"server-only-key"}
		cfg.AlchemyURLs = map[string][]string{"eth-mainnet": {alchemy.srv.URL}}
		cfg.EtherscanKey = "fallback-key"
		cfg.EtherscanURL = scan.srv.URL
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(
		`{"chain":"eth","address":%q}`, evmSelf,
	)))
	if res["status"] != "ok" {
		t.Fatalf("fallback status = %v", res["status"])
	}
	if alchemy.hitCount("/") != 4 {
		t.Fatalf("Alchemy includes category retries for both directions, hits = %d", alchemy.hitCount("/"))
	}
	if scan.hitCount("/") != 3 {
		t.Fatalf("Etherscan fallback feeds = %d", scan.hitCount("/"))
	}
}

func TestEthHistoryWithKey(t *testing.T) {
	scan := newRESTFake(t)
	scan.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("action") == "tokentx" {
			_, _ = fmt.Fprintf(w, `{
				"status":"1","message":"OK",
				"result":[
					{"hash":"0x6666666666666666666666666666666666666666666666666666666666666666","logIndex":"7","from":%q,"to":"0x2222222222222222222222222222222222222222",
					 "value":"2500000","timeStamp":"1700000100","tokenDecimal":"6",
					 "tokenSymbol":"FAKE","contractAddress":"0xdAC17F958D2ee523a2206206994597C13D831ec7",
					 "blockNumber":"4730207","blockHash":"0x022c5e6a3d2487a8ccf8946a2ffb74938bf8e5c8a3f6d91b41c56378a96b5c37",
					 "transactionIndex":"81","confirmations":"1"}
				]}`, evmSelf)
			return
		}
		_, _ = fmt.Fprintf(w, `{
			"status":"1","message":"OK",
			"result":[
				{"hash":"0x6666666666666666666666666666666666666666666666666666666666666666","from":%q,"to":"0x2222222222222222222222222222222222222222","value":"0","timeStamp":"1700000100","isError":"0"},
				{"hash":"0x7777777777777777777777777777777777777777777777777777777777777777","from":"0x2222222222222222222222222222222222222222","to":%q,"value":"2000","timeStamp":"1700000000","isError":"1"}
			]}`, evmSelf, evmSelf)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "test-key"
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q,"limit":10}`, evmSelf)))
	if res["status"] != "ok" {
		t.Fatalf("status = %v", res["status"])
	}
	assertJSONEq(t, `[
		{"id":"0x6666666666666666666666666666666666666666666666666666666666666666:7","hash":"0x6666666666666666666666666666666666666666666666666666666666666666","direction":"out","from":"0x1111111111111111111111111111111111111111","to":"0x2222222222222222222222222222222222222222","amountRaw":"2500000","decimals":6,"symbol":"USDT","contract":"0xdac17f958d2ee523a2206206994597c13d831ec7","verified":true,"timestampMs":1700000100000,"status":"ok"},
		{"id":"0x7777777777777777777777777777777777777777777777777777777777777777","hash":"0x7777777777777777777777777777777777777777777777777777777777777777","direction":"in","from":"0x2222222222222222222222222222222222222222","to":"0x1111111111111111111111111111111111111111","amountRaw":"2000","decimals":18,"symbol":"ETH","verified":true,"timestampMs":1700000000000,"status":"failed"}
	]`, res["records"])

	hits := scan.hitsFor("/")
	if len(hits) != 3 {
		t.Fatalf("expected normal + token + internal Etherscan calls, got %d", len(hits))
	}
	actions := map[string]bool{}
	for _, hit := range hits {
		u, _ := url.Parse(hit.Path)
		q := u.Query()
		actions[q.Get("action")] = true
		for k, want := range map[string]string{
			"chainid": "1", "module": "account",
			"address": evmSelf, "apikey": "test-key", "sort": "desc", "offset": "10",
		} {
			if q.Get(k) != want {
				t.Fatalf("etherscan query %s = %q, want %q (full: %s)", k, q.Get(k), want, hit.Path)
			}
		}
	}
	for _, action := range []string{"txlist", "tokentx", "txlistinternal"} {
		if !actions[action] {
			t.Fatalf("missing concurrent Etherscan action %s: %v", action, actions)
		}
	}
}

func TestEthHistoryKeepsMultipleLogsAndMarksUnknownToken(t *testing.T) {
	const other = "0x2222222222222222222222222222222222222222"
	scan := newRESTFake(t)
	scan.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("action") == "tokentx" {
			_, _ = fmt.Fprintf(w, `{"status":"1","message":"OK","result":[
				{"hash":"0x8888888888888888888888888888888888888888888888888888888888888888","logIndex":"3","from":%q,"to":%q,
				 "value":"1000000","timeStamp":"1700000100","tokenDecimal":"6",
				 "tokenSymbol":"USDT","contractAddress":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
				 "blockNumber":"4730207","blockHash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
				 "transactionIndex":"81","confirmations":"1"},
				{"hash":"0x8888888888888888888888888888888888888888888888888888888888888888","logIndex":"4","from":%q,"to":%q,
				 "value":"2000000","timeStamp":"1700000100","tokenDecimal":"6",
				 "tokenSymbol":"USDT","contractAddress":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
				 "blockNumber":"4730207","blockHash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
				 "transactionIndex":"81","confirmations":"1"}
			]}`, evmSelf, other, evmSelf, other)
			return
		}
		_, _ = fmt.Fprintf(w, `{"status":"1","message":"OK","result":[
			{"hash":"0x8888888888888888888888888888888888888888888888888888888888888888","from":%q,"to":%q,"value":"0","timeStamp":"1700000100","isError":"0"}
		]}`, evmSelf, other)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "test-key"
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	records := res["records"].([]any)
	if len(records) != 2 {
		t.Fatalf("both transfer logs must survive while the zero-value wrapper is removed: %v", records)
	}
	for _, raw := range records {
		record := raw.(map[string]any)
		if record["verified"] != false || record["symbol"] != "USDT" {
			t.Fatalf("symbol-spoofing contracts must remain visibly unverified: %v", record)
		}
	}
	if records[0].(map[string]any)["id"] == records[1].(map[string]any)["id"] {
		t.Fatal("each log needs a distinct event id")
	}
}

func TestOperatorCatalogControlsHistoryVerification(t *testing.T) {
	const contract = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	scan := newRESTFake(t)
	scan.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("action") == "tokentx" {
			_, _ = fmt.Fprintf(w, `{"status":"1","message":"OK","result":[
				{"hash":"0x9999999999999999999999999999999999999999999999999999999999999999","logIndex":"1","from":%q,
				 "to":"0x2222222222222222222222222222222222222222",
				 "value":"123","timeStamp":"1700000100","tokenDecimal":"18",
				 "tokenSymbol":"LOOKALIKE","contractAddress":%q,
				 "blockNumber":"4730207","blockHash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
				 "transactionIndex":"81","confirmations":"1"}
			]}`, evmSelf, contract)
			return
		}
		_, _ = fmt.Fprint(w, `{"status":"1","message":"OK","result":[]}`)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "test-key"
		cfg.OfficialTokens = []handlers.OfficialToken{{
			Network:  "eth-mainnet",
			Symbol:   "KTT",
			Name:     "KT Test Token",
			Contract: contract,
			Decimals: 8,
		}}
	})

	res := result(t, e.rpc(
		"kt_getHistory",
		fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf),
	))
	records := res["records"].([]any)
	if len(records) != 1 {
		t.Fatalf("records = %v", records)
	}
	record := records[0].(map[string]any)
	if record["verified"] != true ||
		record["symbol"] != "KTT" ||
		record["decimals"] != float64(8) {
		t.Fatalf("configured identity must override claimed metadata: %v", record)
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

func TestEthHistoryEtherscanErrorIsNormalized(t *testing.T) {
	scan := newRESTFake(t)
	scan.routeJSON("/", `{"status":"0","message":"NOTOK","result":"Max rate limit reached"}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "k"
	})
	resp := e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	if d := errData(t, errObj); d["message"] != "upstream temporarily unavailable" {
		t.Fatalf("provider error text must not cross the public boundary, got %v", d)
	}
}

func TestEthHistoryEtherscanFailureFallsBackToPublicExplorer(t *testing.T) {
	scan := newRESTFake(t)
	scan.routeJSON("/", `{"status":"0","message":"NOTOK","result":"Max rate limit reached"}`)
	explorer := newRESTFake(t)
	explorer.route("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("action") != "txlist" {
			_, _ = fmt.Fprint(w, `{"status":"1","message":"OK","result":[]}`)
			return
		}
		_, _ = fmt.Fprintf(w, `{
			"status":"1","message":"OK",
			"result":[
				{"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","from":"0x2222222222222222222222222222222222222222","to":%q,"value":"9","timeStamp":"1700000500","isError":"0"}
			]}`, evmSelf)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "bad-or-limited-key"
		cfg.EVMHistoryFallbackURLs = map[string]string{
			"eth-mainnet": explorer.srv.URL,
		}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	assertJSONEq(t, `[
		{"id":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","direction":"in","from":"0x2222222222222222222222222222222222222222","to":"0x1111111111111111111111111111111111111111","amountRaw":"9","decimals":18,"symbol":"ETH","verified":true,"timestampMs":1700000500000,"status":"ok"}
	]`, res["records"])
	// Normal, token and internal feeds are requested concurrently so one slow
	// explorer does not serialize three full timeout windows.
	if scan.hitCount("/") != 3 || explorer.hitCount("/") != 3 {
		t.Fatalf("expected primary then fallback, got scan=%d explorer=%d",
			scan.hitCount("/"), explorer.hitCount("/"))
	}
}

func TestSolanaHistoryWithoutKeyUsesRPC(t *testing.T) {
	node := newRPCFake(t)
	node.result("getSignaturesForAddress", []any{
		map[string]any{
			"signature": "rpc-sig-1",
			"blockTime": 1700000400,
			"err":       nil,
		},
	})
	node.result("getTransaction", map[string]any{
		"meta": map[string]any{
			"preBalances":  []any{5000000, 100},
			"postBalances": []any{3000000, 2000100},
			"preTokenBalances": []any{
				map[string]any{
					"mint":          "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
					"owner":         solSelf,
					"uiTokenAmount": map[string]any{"amount": "3000000", "decimals": 6},
				},
			},
			"postTokenBalances": []any{
				map[string]any{
					"mint":          "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
					"owner":         solSelf,
					"uiTokenAmount": map[string]any{"amount": "1000000", "decimals": 6},
				},
			},
		},
		"transaction": map[string]any{
			"message": map[string]any{
				"accountKeys": []any{
					map[string]any{"pubkey": solSelf, "signer": true},
					map[string]any{"pubkey": solOther, "signer": false},
				},
			},
		},
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.SolanaURLs = []string{node.srv.URL}
	})
	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"solana","address":%q}`, solSelf)))
	if res["status"] != "ok" {
		t.Fatalf("status = %v", res["status"])
	}
	assertJSONEq(t, `[
		{"id":"rpc-sig-1:spl:EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","hash":"rpc-sig-1","direction":"out","from":"9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin","amountRaw":"2000000","decimals":6,"symbol":"USDC","contract":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","verified":true,"timestampMs":1700000400000,"status":"ok"}
	]`, res["records"])
	if node.count("getSignaturesForAddress") != 1 || node.count("getTransaction") != 1 {
		t.Fatalf("expected signature + transaction RPC calls, got %d/%d",
			node.count("getSignaturesForAddress"), node.count("getTransaction"))
	}
}

func TestSolanaHistoryMissingExecutionEvidenceIsUnknown(t *testing.T) {
	node := newRPCFake(t)
	node.result("getSignaturesForAddress", []any{
		map[string]any{"signature": "missing-err", "blockTime": 1700000700},
	})
	node.result("getTransaction", map[string]any{
		"meta": map[string]any{
			"preBalances":  []any{100, 0},
			"postBalances": []any{50, 50},
		},
		"transaction": map[string]any{
			"message": map[string]any{
				"accountKeys": []any{
					map[string]any{"pubkey": solSelf, "signer": true},
					map[string]any{"pubkey": solOther, "signer": false},
				},
			},
		},
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.SolanaURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"solana","address":%q}`, solSelf)))
	records := res["records"].([]any)
	if len(records) != 1 || records[0].(map[string]any)["status"] != "unknown" {
		t.Fatalf("missing signature err must remain unknown: %v", records)
	}
}

func TestSolanaHistoryFindsIncomingSPLTransferThroughATA(t *testing.T) {
	const (
		ata       = "Ata111111111111111111111111111111111111111"
		senderATA = "Ata222222222222222222222222222222222222222"
		mint      = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
	)
	node := newRPCFake(t)
	node.result("getTokenAccountsByOwner", map[string]any{
		"value": []any{map[string]any{"pubkey": ata}},
	})
	node.handle("getSignaturesForAddress", func(params []json.RawMessage) (any, map[string]any) {
		var account string
		_ = json.Unmarshal(params[0], &account)
		if account != ata {
			return []any{}, nil
		}
		return []any{map[string]any{
			"signature": "ata-sig",
			"blockTime": 1700000600,
			"err":       nil,
		}}, nil
	})
	node.result("getTransaction", map[string]any{
		"meta": map[string]any{
			"preBalances":  []any{100, 100},
			"postBalances": []any{100, 100},
			"preTokenBalances": []any{
				map[string]any{"accountIndex": 0, "mint": mint, "owner": solOther,
					"uiTokenAmount": map[string]any{"amount": "3000000", "decimals": 6}},
				map[string]any{"accountIndex": 1, "mint": mint, "owner": solSelf,
					"uiTokenAmount": map[string]any{"amount": "1000000", "decimals": 6}},
			},
			"postTokenBalances": []any{
				map[string]any{"accountIndex": 0, "mint": mint, "owner": solOther,
					"uiTokenAmount": map[string]any{"amount": "1000000", "decimals": 6}},
				map[string]any{"accountIndex": 1, "mint": mint, "owner": solSelf,
					"uiTokenAmount": map[string]any{"amount": "3000000", "decimals": 6}},
			},
		},
		"transaction": map[string]any{
			"message": map[string]any{
				// Owner deliberately absent: an incoming SPL transfer may
				// touch only its associated token account.
				"accountKeys": []any{
					map[string]any{"pubkey": senderATA},
					map[string]any{"pubkey": ata},
				},
				"instructions": []any{map[string]any{
					"program": "spl-token",
					"parsed": map[string]any{
						"type": "transfer",
						"info": map[string]any{
							"source": senderATA, "destination": ata, "authority": solOther,
						},
					},
				}},
			},
		},
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.SolanaURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc("kt_getHistory",
		fmt.Sprintf(`{"chain":"solana","address":%q}`, solSelf)))
	assertJSONEq(t, `[
		{"id":"ata-sig:spl:EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","hash":"ata-sig","direction":"in","from":"4Nd1mYtBS4yPPsSycFSCA1WzX7yBW2cVDpn9WzWtLDwT","to":"9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin","amountRaw":"2000000","decimals":6,"symbol":"USDC","contract":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","verified":true,"timestampMs":1700000600000,"status":"ok"}
	]`, res["records"])
	if node.count("getSignaturesForAddress") != 2 {
		t.Fatalf("must query owner and deduplicated ATA signatures, got %d",
			node.count("getSignaturesForAddress"))
	}
}

func TestSolanaZeroMovementProgramActivityIsNotTransfer(t *testing.T) {
	node := newRPCFake(t)
	node.result("getSignaturesForAddress", []any{
		map[string]any{"signature": "program-only", "blockTime": 1700000400, "err": nil},
	})
	node.result("getTransaction", map[string]any{
		"meta": map[string]any{
			"preBalances":  []any{5000000, 100},
			"postBalances": []any{5000000, 100},
		},
		"transaction": map[string]any{
			"message": map[string]any{
				"accountKeys": []any{
					map[string]any{"pubkey": solSelf, "signer": false},
					map[string]any{"pubkey": solOther, "signer": true},
				},
			},
		},
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.SolanaURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"solana","address":%q}`, solSelf)))
	assertJSONEq(t, `[]`, res["records"])
}

func TestSolanaHeliusFailureFallsBackToRPC(t *testing.T) {
	hel := newRESTFake(t)
	hel.route("/", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	})
	node := newRPCFake(t)
	node.result("getSignaturesForAddress", []any{
		map[string]any{"signature": "fallback-sig", "blockTime": 1700000600, "err": nil},
	})
	node.result("getTransaction", map[string]any{
		"meta": map[string]any{
			"preBalances":  []any{100, 20},
			"postBalances": []any{40, 80},
		},
		"transaction": map[string]any{
			"message": map[string]any{
				"accountKeys": []any{
					map[string]any{"pubkey": solOther, "signer": true},
					map[string]any{"pubkey": solSelf, "signer": false},
				},
			},
		},
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.HeliusURL = hel.srv.URL
		cfg.HeliusKey = "limited-key"
		cfg.SolanaURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"solana","address":%q}`, solSelf)))
	assertJSONEq(t, `[
		{"id":"fallback-sig","hash":"fallback-sig","direction":"in","to":"9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin","amountRaw":"60","decimals":9,"symbol":"SOL","verified":true,"timestampMs":1700000600000,"status":"ok"}
	]`, res["records"])
}

func TestSolanaHistoryWithHeliusKey(t *testing.T) {
	hel := newRESTFake(t)
	hel.routeJSON("/", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[
		{"signature":"sig1","slot":1001,"blockTime":1700000200,"type":"transfer",
		 "fromUserAccount":%q,"toUserAccount":%q,
		 "mint":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
		 "amount":"2500000","decimals":6,"uiAmount":"2.5","confirmationStatus":"finalized",
		 "transactionIdx":1,"instructionIdx":2,"innerInstructionIdx":0},
		{"signature":"sig2","slot":1002,"blockTime":1700000100,"type":"transfer",
		 "fromUserAccount":%q,"toUserAccount":%q,
		 "mint":"So11111111111111111111111111111111111111111",
		 "amount":"123","decimals":9,"uiAmount":"0.000000123","confirmationStatus":"finalized",
		 "transactionIdx":2,"instructionIdx":3,"innerInstructionIdx":null},
		{"signature":"sig3","slot":1003,"blockTime":1700000050,"type":"transfer",
		 "fromUserAccount":%q,"toUserAccount":%q,
		 "mint":"Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
		 "amount":"42000000","decimals":6,"uiAmount":"42","confirmationStatus":"finalized",
		 "transactionIdx":3,"instructionIdx":4,"innerInstructionIdx":null}
	]}}`, solSelf, solOther, solOther, solSelf, solOther, solSelf))
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.HeliusURL = hel.srv.URL
		cfg.HeliusKey = "helius-key"
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"solana","address":%q}`, solSelf)))
	if res["status"] != "ok" {
		t.Fatalf("status = %v", res["status"])
	}
	assertJSONEq(t, `[
		{"id":"sig1:1:2:0","hash":"sig1","direction":"out","from":"9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin","to":"4Nd1mYtBS4yPPsSycFSCA1WzX7yBW2cVDpn9WzWtLDwT","amountRaw":"2500000","decimals":6,"symbol":"USDC","contract":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","verified":true,"timestampMs":1700000200000,"status":"ok"},
		{"id":"sig2:2:3:-1","hash":"sig2","direction":"in","from":"4Nd1mYtBS4yPPsSycFSCA1WzX7yBW2cVDpn9WzWtLDwT","to":"9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin","amountRaw":"123","decimals":9,"symbol":"SOL","verified":true,"timestampMs":1700000100000,"status":"ok"},
		{"id":"sig3:3:4:-1","hash":"sig3","direction":"in","from":"4Nd1mYtBS4yPPsSycFSCA1WzX7yBW2cVDpn9WzWtLDwT","to":"9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin","amountRaw":"42000000","decimals":6,"symbol":"USDT","contract":"Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB","verified":true,"timestampMs":1700000050000,"status":"ok"}
	]`, res["records"])

	u, _ := url.Parse(hel.hitsFor("/")[0].Path)
	if u.Query().Get("api-key") != "helius-key" {
		t.Fatal("Helius api-key must be attached by the gateway")
	}
	var request map[string]any
	if err := json.Unmarshal([]byte(hel.hitsFor("/")[0].Body), &request); err != nil {
		t.Fatal(err)
	}
	if request["method"] != "getTransfersByAddress" {
		t.Fatalf("deprecated Helius enhanced-transactions endpoint must not be used: %v", request)
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
	if got := grid.hitCount("/v1/accounts/"); got != 3 { // trc20 + native + internal, once each
		t.Fatalf("second call within 30s TTL must be cached, upstream hits = %d", got)
	}
	e.clk.Advance(31 * time.Second)
	result(t, e.rpc("kt_getHistory", p))
	if got := grid.hitCount("/v1/accounts/"); got != 6 {
		t.Fatalf("expected refetch after TTL, upstream hits = %d", got)
	}
	// A different limit is a different cache key.
	result(t, e.rpc("kt_getHistory", fmt.Sprintf(`{"chain":"tron","address":%q,"limit":3}`, tronSelfB58)))
	if got := grid.hitCount("/v1/accounts/"); got != 9 {
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
	if len(out.Data) == 0 || out.Data[0]["transaction_id"] != tronTx1 {
		t.Fatalf("trc20 route not matched correctly: %v", out.Data)
	}
}

// A native-coin history row must carry the chain's own denomination, not the
// scale Alchemy happens to report. `decimal` is upstream display metadata; the
// native unit of a chain is a protocol constant the gateway already knows (it
// is where the sibling `symbol` field comes from). Accepting 9 for an EVM
// chain turns a 1 BNB transfer into an apparent 1,000,000,000 BNB row.
func TestAlchemyNativeRowUsesChainDenomination(t *testing.T) {
	alchemy := newRESTFake(t)
	alchemy.route("/", func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Params []map[string]any `json:"params"`
		}
		_ = json.NewDecoder(r.Body).Decode(&request)
		w.Header().Set("Content-Type", "application/json")
		if request.Params[0]["toAddress"] != nil {
			_, _ = fmt.Fprint(w, `{"jsonrpc":"2.0","id":1,"result":{"transfers":[]}}`)
			return
		}
		// Well-formed in every respect except the claimed denomination.
		_, _ = fmt.Fprintf(w, `{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
			"uniqueId":"0xbnb:external","blockNum":"0x200","hash":"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
			"from":%q,"to":"0x2222222222222222222222222222222222222222",
			"asset":"BNB","category":"external",
			"rawContract":{"value":"0xde0b6b3a7640000","address":null,"decimal":"0x9"},
			"metadata":{"blockTimestamp":"2026-07-29T01:01:00Z"}
		}]}}`, evmSelf)
	})
	etherscan := newRESTFake(t)
	etherscan.routeJSON("/", `{"status":"1","message":"OK","result":[]}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.AlchemyKeys = []string{"server-only-key"}
		cfg.AlchemyURLs = map[string][]string{"bnb-testnet": {alchemy.srv.URL}}
		cfg.EtherscanKey = "fallback-key"
		cfg.EtherscanURL = etherscan.srv.URL
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(
		`{"chain":"bnb","network":"bnb-testnet","address":%q}`, evmSelf,
	)))
	assertJSONEq(t, `[
		{"id":"0xbnb:external","hash":"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","direction":"out","from":"0x1111111111111111111111111111111111111111","to":"0x2222222222222222222222222222222222222222","amountRaw":"1000000000000000000","decimals":18,"symbol":"BNB","verified":true,"timestampMs":1785286860000,"status":"ok"}
	]`, res["records"])
}

// Pins the upstream contract the native branch relies on: `rawContract.decimal`
// is REQUIRED, and a row missing it invalidates the whole Alchemy page rather
// than silently dropping that row. If this ever loosens, the native branch
// starts losing transfers instead of failing over.
func TestAlchemyRowWithoutDecimalRejectsWholePage(t *testing.T) {
	alchemy := newRESTFake(t)
	alchemy.routeJSON("/", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
		"uniqueId":"0xbnb:external","blockNum":"0x200","hash":"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
		"from":%q,"to":"0x2222222222222222222222222222222222222222",
		"asset":"BNB","category":"external",
		"rawContract":{"value":"0xde0b6b3a7640000","address":null},
		"metadata":{"blockTimestamp":"2026-07-29T01:01:00Z"}
	}]}}`, evmSelf))
	etherscan := newRESTFake(t)
	etherscan.routeJSON("/", `{"status":"1","message":"OK","result":[]}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.AlchemyKeys = []string{"server-only-key"}
		cfg.AlchemyURLs = map[string][]string{"bnb-testnet": {alchemy.srv.URL}}
		cfg.EtherscanKey = "fallback-key"
		cfg.EtherscanURL = etherscan.srv.URL
	})

	res := result(t, e.rpc("kt_getHistory", fmt.Sprintf(
		`{"chain":"bnb","network":"bnb-testnet","address":%q}`, evmSelf,
	)))
	assertJSONEq(t, `[]`, res["records"])
	if etherscan.hitCount("/") == 0 {
		t.Fatal("a page missing rawContract.decimal must fail over, not be partially accepted")
	}
}

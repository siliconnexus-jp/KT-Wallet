package handlers_test

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"testing"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

// newEthPairEnv wires separate fakes for eth-mainnet and eth-sepolia so tests
// can prove which network an upstream call landed on.
func newEthPairEnv(t *testing.T) (mainnet, sepolia *rpcFake, e *env) {
	t.Helper()
	mainnet = newRPCFake(t)
	sepolia = newRPCFake(t)
	mainnet.result("eth_getBalance", "0x1") // 1 wei on mainnet
	sepolia.result("eth_getBalance", "0x2") // 2 wei on sepolia
	e = newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{mainnet.srv.URL}
		cfg.EthSepoliaURLs = []string{sepolia.srv.URL}
	})
	return mainnet, sepolia, e
}

func TestNetworkOmittedUsesMainnetUpstream(t *testing.T) {
	mainnet, sepolia, e := newEthPairEnv(t)

	res := result(t, e.rpc("kt_getBalances", balancesParams("eth", evmSelf, "")))
	if res["native"].(map[string]any)["raw"] != "1" {
		t.Fatalf("omitted network must answer from mainnet: %v", res)
	}
	if mainnet.count("eth_getBalance") != 1 || sepolia.totalCalls() != 0 {
		t.Fatalf("omitted network must hit only the mainnet upstream (mainnet=%d, sepolia=%d)",
			mainnet.count("eth_getBalance"), sepolia.totalCalls())
	}
}

func TestSepoliaBalancesHitSepoliaUpstream(t *testing.T) {
	mainnet, sepolia, e := newEthPairEnv(t)

	res := result(t, e.rpc("kt_getBalances",
		fmt.Sprintf(`{"chain":"eth","network":"eth-sepolia","address":%q}`, evmSelf)))
	if res["native"].(map[string]any)["raw"] != "2" {
		t.Fatalf("sepolia request must answer from the sepolia upstream: %v", res)
	}
	if sepolia.count("eth_getBalance") != 1 || mainnet.totalCalls() != 0 {
		t.Fatalf("sepolia request must hit only the sepolia upstream (mainnet=%d, sepolia=%d)",
			mainnet.totalCalls(), sepolia.count("eth_getBalance"))
	}
}

func TestBalanceCacheIsolatedPerNetwork(t *testing.T) {
	mainnet, sepolia, e := newEthPairEnv(t)

	pMain := balancesParams("eth", evmSelf, "")
	pSepolia := fmt.Sprintf(`{"chain":"eth","network":"eth-sepolia","address":%q}`, evmSelf)

	// Same address on two networks: two distinct upstream fetches.
	if raw := result(t, e.rpc("kt_getBalances", pMain))["native"].(map[string]any)["raw"]; raw != "1" {
		t.Fatalf("mainnet raw = %v", raw)
	}
	if raw := result(t, e.rpc("kt_getBalances", pSepolia))["native"].(map[string]any)["raw"]; raw != "2" {
		t.Fatalf("sepolia raw = %v", raw)
	}
	if mainnet.count("eth_getBalance") != 1 || sepolia.count("eth_getBalance") != 1 {
		t.Fatalf("each network must fetch once (mainnet=%d, sepolia=%d)",
			mainnet.count("eth_getBalance"), sepolia.count("eth_getBalance"))
	}

	// Repeats within the TTL are served from each network's own cache entry —
	// and a sepolia answer is never recycled for mainnet or vice versa.
	if raw := result(t, e.rpc("kt_getBalances", pMain))["native"].(map[string]any)["raw"]; raw != "1" {
		t.Fatalf("cached mainnet answer corrupted: %v", raw)
	}
	if raw := result(t, e.rpc("kt_getBalances", pSepolia))["native"].(map[string]any)["raw"]; raw != "2" {
		t.Fatalf("cached sepolia answer corrupted: %v", raw)
	}
	if mainnet.count("eth_getBalance") != 1 || sepolia.count("eth_getBalance") != 1 {
		t.Fatalf("second round must be cached per network (mainnet=%d, sepolia=%d)",
			mainnet.count("eth_getBalance"), sepolia.count("eth_getBalance"))
	}

	// Explicit "eth-mainnet" and omitted network share one cache entry.
	if raw := result(t, e.rpc("kt_getBalances",
		fmt.Sprintf(`{"chain":"eth","network":"eth-mainnet","address":%q}`, evmSelf)))["native"].(map[string]any)["raw"]; raw != "1" {
		t.Fatalf("explicit mainnet raw = %v", raw)
	}
	if mainnet.count("eth_getBalance") != 1 {
		t.Fatalf("explicit eth-mainnet must share the omitted-network cache entry, fetches = %d",
			mainnet.count("eth_getBalance"))
	}
}

func TestUnknownNetworkRejected(t *testing.T) {
	node := newRPCFake(t) // must never be called
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	for _, call := range []struct{ method, params string }{
		{"kt_getBalances", fmt.Sprintf(`{"chain":"eth","network":"eth-goerli","address":%q}`, evmSelf)},
		{"kt_getChainParams", fmt.Sprintf(`{"chain":"eth","network":"mainnet","address":%q}`, evmSelf)},
		{"kt_getHistory", fmt.Sprintf(`{"chain":"eth","network":"sepolia","address":%q}`, evmSelf)},
		{"kt_broadcast", `{"chain":"eth","network":"eth","payload":"0xab"}`},
	} {
		errObj := assertErrCode(t, e.rpc(call.method, call.params), rpc.CodeInvalidParams)
		if msg, _ := errObj["message"].(string); !strings.Contains(msg, `"network"`) {
			t.Fatalf("%s: unknown-network error must name the field, got %q", call.method, msg)
		}
	}
	if node.totalCalls() != 0 {
		t.Fatalf("unknown network must never reach an upstream, saw %d calls", node.totalCalls())
	}
}

func TestNetworkChainMismatchRejected(t *testing.T) {
	node := newRPCFake(t) // must never be called
	grid := newRESTFake(t)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.PolygonURLs = []string{node.srv.URL}
		cfg.SolanaURLs = []string{node.srv.URL}
		cfg.TronURL = grid.srv.URL
	})

	for _, call := range []struct{ method, params string }{
		{"kt_getBalances", fmt.Sprintf(`{"chain":"eth","network":"tron-nile","address":%q}`, evmSelf)},
		{"kt_getBalances", fmt.Sprintf(`{"chain":"tron","network":"eth-mainnet","address":%q}`, tronSelfB58)},
		{"kt_getBalances", fmt.Sprintf(`{"chain":"solana","network":"eth-sepolia","address":%q}`, solSelf)},
		{"kt_getChainParams", fmt.Sprintf(`{"chain":"polygon","network":"eth-sepolia","address":%q}`, evmSelf)},
		{"kt_getHistory", fmt.Sprintf(`{"chain":"eth","network":"polygon-amoy","address":%q}`, evmSelf)},
		{"kt_broadcast", `{"chain":"polygon","network":"sol-devnet","payload":"0xab"}`},
	} {
		errObj := assertErrCode(t, e.rpc(call.method, call.params), rpc.CodeInvalidParams)
		if msg, _ := errObj["message"].(string); !strings.Contains(msg, `"network"`) {
			t.Fatalf("%s %s: mismatch error must name the field, got %q", call.method, call.params, msg)
		}
	}
	if n := node.totalCalls() + len(grid.hitsFor("/")); n != 0 {
		t.Fatalf("chain/network mismatch must never reach an upstream, saw %d calls", n)
	}
}

func TestSepoliaChainParams(t *testing.T) {
	mainnet := newRPCFake(t) // must never be called
	sepolia := newRPCFake(t)
	sepolia.result("eth_getTransactionCount", "0x5")
	sepolia.nodeError("eth_feeHistory", -32601, "method not found") // forces the gasPrice fallback
	sepolia.result("eth_gasPrice", "0x64")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{mainnet.srv.URL}
		cfg.EthSepoliaURLs = []string{sepolia.srv.URL}
	})

	res := result(t, e.rpc("kt_getChainParams",
		fmt.Sprintf(`{"chain":"eth","network":"eth-sepolia","address":%q}`, evmSelf)))
	if res["nonce"] != "5" {
		t.Fatalf("nonce must come from the sepolia node, got %v", res["nonce"])
	}
	if mainnet.totalCalls() != 0 {
		t.Fatalf("sepolia chain params must not touch mainnet, saw %d calls", mainnet.totalCalls())
	}
}

func TestTronNileHistory(t *testing.T) {
	mainGrid := newRESTFake(t) // must never be called
	nile := tronGridFixture(t) // TronGrid response shapes are identical on nile
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TronURL = mainGrid.srv.URL
		cfg.TronNileURL = nile.srv.URL
	})

	res := result(t, e.rpc("kt_getHistory",
		fmt.Sprintf(`{"chain":"tron","network":"tron-nile","address":%q}`, tronSelfB58)))
	if res["status"] != "ok" {
		t.Fatalf("nile history must be supported through TronGrid, got %v", res["status"])
	}
	assertJSONEq(t, `[
		{"id":"t1:trc20:TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t:0","hash":"t1","direction":"out","amountRaw":"1000000","decimals":6,"symbol":"USDT","contract":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","verified":false,"timestampMs":5000,"status":"ok"},
		{"id":"n1","hash":"n1","direction":"in","amountRaw":"7000000","decimals":6,"symbol":"TRX","verified":true,"timestampMs":4000,"status":"ok"},
		{"id":"tdup:trc20:TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t:1","hash":"tdup","direction":"in","amountRaw":"250000","decimals":6,"symbol":"USDT","contract":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","verified":false,"timestampMs":3000,"status":"ok"},
		{"id":"n3","hash":"n3","direction":"out","amountRaw":"42","decimals":6,"symbol":"TRX","verified":true,"timestampMs":2000,"status":"failed"}
	]`, res["records"])
	if got := nile.hitCount("/v1/accounts/"); got != 2 { // trc20 + native
		t.Fatalf("nile base URL must serve the history calls, hits = %d", got)
	}
	if len(mainGrid.hitsFor("/")) != 0 {
		t.Fatal("tron-nile history must never touch the mainnet TronGrid")
	}
}

func TestSepoliaHistoryUsesEtherscanChainID(t *testing.T) {
	scan := newRESTFake(t)
	scan.routeJSON("/", `{"status":"1","message":"OK","result":[]}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EtherscanURL = scan.srv.URL
		cfg.EtherscanKey = "k"
	})

	for network, wantChainID := range map[string]string{
		"eth-sepolia":  "11155111",
		"polygon-amoy": "80002",
	} {
		chain := "eth"
		if network == "polygon-amoy" {
			chain = "polygon"
		}
		res := result(t, e.rpc("kt_getHistory",
			fmt.Sprintf(`{"chain":%q,"network":%q,"address":%q}`, chain, network, evmSelf)))
		if res["status"] != "ok" {
			t.Fatalf("%s: status = %v", network, res["status"])
		}
		hits := scan.hitsFor("/")
		u, _ := url.Parse(hits[len(hits)-1].Path)
		if got := u.Query().Get("chainid"); got != wantChainID {
			t.Fatalf("%s must query chainid=%s, got %q", network, wantChainID, got)
		}
	}
}

func TestSepoliaHistoryWithoutKeyUnsupported(t *testing.T) {
	scan := newRESTFake(t) // must not be called
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EtherscanURL = scan.srv.URL })

	res := result(t, e.rpc("kt_getHistory",
		fmt.Sprintf(`{"chain":"eth","network":"eth-sepolia","address":%q}`, evmSelf)))
	assertJSONEq(t, `{"status":"unsupported","records":[]}`, res)
	if len(scan.hitsFor("/")) != 0 {
		t.Fatal("without ETHERSCAN_API_KEY no upstream call may happen")
	}
}

func TestSolDevnetHistoryUsesDevnetHelius(t *testing.T) {
	mainHel := newRESTFake(t) // must never be called
	devHel := newRESTFake(t)
	devHel.routeJSON("/", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[
		{"signature":"dsig1","blockTime":1700000300,"type":"transfer",
		 "fromUserAccount":%q,"toUserAccount":%q,
		 "mint":"So11111111111111111111111111111111111111111",
		 "amount":"42","decimals":9,"confirmationStatus":"finalized",
		 "transactionIdx":1,"instructionIdx":2}
	]}}`, solSelf, solOther))
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.HeliusURL = mainHel.srv.URL
		cfg.HeliusDevnetURL = devHel.srv.URL
		cfg.HeliusKey = "helius-key"
	})

	res := result(t, e.rpc("kt_getHistory",
		fmt.Sprintf(`{"chain":"solana","network":"sol-devnet","address":%q}`, solSelf)))
	assertJSONEq(t, `[
		{"id":"dsig1:1:2:-1","hash":"dsig1","direction":"out","amountRaw":"42","decimals":9,"symbol":"SOL","verified":true,"timestampMs":1700000300000,"status":"ok"}
	]`, res["records"])
	if len(mainHel.hitsFor("/")) != 0 {
		t.Fatal("sol-devnet history must use the devnet Helius endpoint, not mainnet")
	}
	u, _ := url.Parse(devHel.hitsFor("/")[0].Path)
	if u.Query().Get("api-key") != "helius-key" {
		t.Fatal("the shared Helius key must be attached to devnet calls")
	}
}

func TestBroadcastAmoyForwardsToAmoyUpstream(t *testing.T) {
	polygonMain := newRPCFake(t) // must never be called
	amoy := newRPCFake(t)
	amoy.result("eth_sendRawTransaction", "0xamoyhash")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.PolygonURLs = []string{polygonMain.srv.URL}
		cfg.PolygonAmoyURLs = []string{amoy.srv.URL}
	})

	resp := e.rpc("kt_broadcast",
		fmt.Sprintf(`{"chain":"polygon","network":"polygon-amoy","payload":%q}`, evmRawTx))
	assertJSONEq(t, `{"txHash":"0xamoyhash"}`, result(t, resp))

	params := amoy.params("eth_sendRawTransaction")
	if len(params) != 1 {
		t.Fatalf("eth_sendRawTransaction takes exactly one param, got %d", len(params))
	}
	var sent string
	_ = json.Unmarshal(params[0], &sent)
	if sent != evmRawTx {
		t.Fatalf("payload must be forwarded verbatim to amoy:\n sent %s\n want %s", sent, evmRawTx)
	}
	if polygonMain.totalCalls() != 0 {
		t.Fatalf("amoy broadcast must never touch polygon mainnet, saw %d calls", polygonMain.totalCalls())
	}
}

func TestHistoryCacheIsolatedPerNetwork(t *testing.T) {
	mainGrid := tronGridFixture(t)
	nile := tronGridFixture(t)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TronURL = mainGrid.srv.URL
		cfg.TronNileURL = nile.srv.URL
	})

	pMain := fmt.Sprintf(`{"chain":"tron","address":%q}`, tronSelfB58)
	pNile := fmt.Sprintf(`{"chain":"tron","network":"tron-nile","address":%q}`, tronSelfB58)
	result(t, e.rpc("kt_getHistory", pMain))
	result(t, e.rpc("kt_getHistory", pNile)) // must not be served from the mainnet cache entry
	result(t, e.rpc("kt_getHistory", pMain))
	result(t, e.rpc("kt_getHistory", pNile))
	if got := mainGrid.hitCount("/v1/accounts/"); got != 2 { // trc20 + native, fetched once
		t.Fatalf("mainnet history should be fetched once then cached, hits = %d", got)
	}
	if got := nile.hitCount("/v1/accounts/"); got != 2 {
		t.Fatalf("nile history should be fetched once then cached, hits = %d", got)
	}
}

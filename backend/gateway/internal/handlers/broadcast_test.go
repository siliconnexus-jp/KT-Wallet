package handlers_test

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

const (
	evmRawTx  = "0x02f87001830f4240843b9aca00850df847580082520894111111111111111111111111111111111111111187038d7ea4c6800080c001a0aa" // arbitrary even-length hex
	solRawTx  = "AXNpZ25hdHVyZS1ieXRlcy1oZXJlLW5vdC1yZWFslgEAAQJzb2xhbmEtdHgtYnl0ZXM="                                               // valid base64
	tronRawTx = `{"raw_data":{"contract":[{"type":"TransferContract"}]},"signature":["ab12"],"txID":"deadbeef"}`
)

func TestBroadcastEVMForwardsExactPayload(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xhash123")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx))
	assertJSONEq(t, `{"txHash":"0xhash123"}`, result(t, resp))

	params := node.params("eth_sendRawTransaction")
	if len(params) != 1 {
		t.Fatalf("eth_sendRawTransaction takes exactly one param, got %d", len(params))
	}
	var sent string
	_ = json.Unmarshal(params[0], &sent)
	if sent != evmRawTx {
		t.Fatalf("payload must be forwarded verbatim:\n sent %s\n want %s", sent, evmRawTx)
	}
}

func TestBroadcastSolanaBase64(t *testing.T) {
	node := newRPCFake(t)
	node.result("sendTransaction", "5sig...abc")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.SolanaURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"solana","payload":%q}`, solRawTx))
	assertJSONEq(t, `{"txHash":"5sig...abc"}`, result(t, resp))

	params := node.params("sendTransaction")
	if len(params) != 2 {
		t.Fatalf("sendTransaction should get [payload, opts], got %d params", len(params))
	}
	var sent string
	_ = json.Unmarshal(params[0], &sent)
	if sent != solRawTx {
		t.Fatal("solana payload must be forwarded verbatim")
	}
	var opts map[string]string
	_ = json.Unmarshal(params[1], &opts)
	if opts["encoding"] != "base64" {
		t.Fatalf("sendTransaction must request base64 encoding, got %v", opts)
	}
}

func TestBroadcastTronForwardsJSONBody(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON("/wallet/broadcasttransaction", `{"result":true,"txid":"deadbeef"}`)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"tron","payload":%q}`, tronRawTx))
	assertJSONEq(t, `{"txHash":"deadbeef"}`, result(t, resp))

	hits := grid.hitsFor("/wallet/broadcasttransaction")
	if len(hits) != 1 {
		t.Fatalf("expected 1 broadcast POST, got %d", len(hits))
	}
	if hits[0].Body != tronRawTx {
		t.Fatalf("tron payload must be forwarded verbatim:\n sent %s\n want %s", hits[0].Body, tronRawTx)
	}
}

// The wallet-core signers emit the full signed Transaction protobuf, which
// only /wallet/broadcasthex accepts. Routing it to /wallet/broadcasttransaction
// (which dereferences `raw_data`) made every TRON transfer fail with a bare
// NullPointerException from the node.
func TestBroadcastTronHexPayloadUsesBroadcastHex(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON("/wallet/broadcasthex", `{"result":true,"txid":"deadbeef"}`)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	payload := `{"transaction":"0a02ab12","txID":"deadbeef"}`
	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"tron","payload":%q}`, payload))
	assertJSONEq(t, `{"txHash":"deadbeef"}`, result(t, resp))

	if hits := grid.hitsFor("/wallet/broadcasttransaction"); len(hits) != 0 {
		t.Fatalf("a hex payload must not hit broadcasttransaction, got %d", len(hits))
	}
	hits := grid.hitsFor("/wallet/broadcasthex")
	if len(hits) != 1 {
		t.Fatalf("expected 1 broadcasthex POST, got %d", len(hits))
	}
	// txID must not ride along: TronGrid rejects unknown body fields.
	if want := `{"transaction":"0a02ab12"}`; hits[0].Body != want {
		t.Fatalf("broadcasthex body:\n got %s\nwant %s", hits[0].Body, want)
	}
}

// TronGrid answers node-level failures with a top-level `Error` and no
// code/message; reading only the latter reported an empty reason.
func TestBroadcastTronSurfacesTopLevelError(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON("/wallet/broadcasthex",
		`{"Error":"class java.lang.NullPointerException : null"}`)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	payload := `{"transaction":"0a02ab12"}`
	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"tron","payload":%q}`, payload))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	msg, _ := errObj["message"].(string)
	if msg != "upstream rejected request" {
		t.Fatalf("untrusted top-level Error must be normalized, got %q", msg)
	}
}

func TestBroadcastEVMNodeRejection(t *testing.T) {
	node := newRPCFake(t)
	node.nodeError("eth_sendRawTransaction", -32000, "nonce too low")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	if errObj["message"] != "transaction nonce is too low" {
		t.Fatalf("node rejection must be normalized, got %q", errObj["message"])
	}
	if d := errData(t, errObj); d["message"] != "transaction nonce is too low" {
		t.Fatalf("data.message must carry the normalized rejection, got %v", d)
	}
}

func TestBroadcastEVMTransportFailureIsUnknownAndNeverFailsOver(t *testing.T) {
	var firstHits atomic.Int64
	first := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		firstHits.Add(1)
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	t.Cleanup(first.Close)
	second := newRPCFake(t)
	second.result("eth_sendRawTransaction", "0xmust-not-be-used")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{first.URL, second.srv.URL}
	})

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx))
	errObj := assertErrCode(t, resp, rpc.CodeSubmissionUnknown)
	if errObj["message"] != "submission_unknown" {
		t.Fatalf("lost response must be submission_unknown, got %v", errObj)
	}
	if firstHits.Load() != 1 || second.count("eth_sendRawTransaction") != 0 {
		t.Fatalf("EVM broadcast must be single-shot, got %d/%d", firstHits.Load(), second.count("eth_sendRawTransaction"))
	}
}

func TestBroadcastSolanaTransportFailureIsUnknownAndNeverFailsOver(t *testing.T) {
	var firstHits atomic.Int64
	first := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		firstHits.Add(1)
		w.WriteHeader(http.StatusBadGateway)
	}))
	t.Cleanup(first.Close)
	second := newRPCFake(t)
	second.result("sendTransaction", "must-not-be-used")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.SolanaURLs = []string{first.URL, second.srv.URL}
	})

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"solana","payload":%q}`, solRawTx))
	assertErrCode(t, resp, rpc.CodeSubmissionUnknown)
	if firstHits.Load() != 1 || second.count("sendTransaction") != 0 {
		t.Fatalf("Solana broadcast must be single-shot, got %d/%d", firstHits.Load(), second.count("sendTransaction"))
	}
}

func TestBroadcastTronTransportFailureIsUnknown(t *testing.T) {
	grid := newRESTFake(t)
	grid.route("/wallet/broadcasttransaction", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"tron","payload":%q}`, tronRawTx))
	errObj := assertErrCode(t, resp, rpc.CodeSubmissionUnknown)
	if errObj["message"] != "submission_unknown" {
		t.Fatalf("lost TronGrid response must be submission_unknown, got %v", errObj)
	}
	if hits := grid.hitsFor("/wallet/broadcasttransaction"); len(hits) != 1 {
		t.Fatalf("TRON broadcast must be attempted once, got %d", len(hits))
	}
}

func TestBroadcastTronRejectionDecodesHexMessage(t *testing.T) {
	grid := newRESTFake(t)
	hexMsg := hex.EncodeToString([]byte("Validate signature error"))
	grid.routeJSON("/wallet/broadcasttransaction",
		fmt.Sprintf(`{"result":false,"code":"SIGERROR","message":%q}`, hexMsg))
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"tron","payload":%q}`, tronRawTx))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	msg, _ := errObj["message"].(string)
	if msg != "transaction signature verification failed" {
		t.Fatalf("Tron rejection must be actionable without reflecting provider text, got %q", msg)
	}
}

func TestBroadcastSolanaNodeRejection(t *testing.T) {
	node := newRPCFake(t)
	node.nodeError("sendTransaction", -32002, "Transaction simulation failed: Blockhash not found")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.SolanaURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"solana","payload":%q}`, solRawTx))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	if errObj["message"] != "transaction blockhash is no longer valid" {
		t.Fatalf("Solana rejection must be normalized: %v", errObj["message"])
	}
}

func TestBroadcastMalformedPayloadNeverHitsUpstream(t *testing.T) {
	evmNode := newRPCFake(t)
	solNode := newRPCFake(t)
	grid := newRESTFake(t)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{evmNode.srv.URL}
		cfg.SolanaURLs = []string{solNode.srv.URL}
		cfg.TronURL = grid.srv.URL
	})

	cases := []struct {
		name    string
		chain   string
		payload string
	}{
		{"evm not hex", "eth", "nothex"},
		{"evm missing 0x", "eth", "deadbeef"},
		{"evm odd length", "eth", "0xabc"},
		{"evm 0x only", "polygon", "0x"},
		{"evm blank", "eth", ""},
		{"solana not base64", "solana", "!!!not-base64!!!"},
		{"solana empty", "solana", ""},
		{"tron not json", "tron", "not json"},
		{"tron json array", "tron", "[1,2,3]"},
		{"tron truncated json", "tron", `{"txID":`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":%q,"payload":%q}`, tc.chain, tc.payload))
			assertErrCode(t, resp, rpc.CodeInvalidParams)
		})
	}
	if n := evmNode.totalCalls() + solNode.totalCalls() + len(grid.hitsFor("/")); n != 0 {
		t.Fatalf("malformed payloads must be rejected before any upstream call, saw %d", n)
	}
}

func TestBroadcastStrictSchemaRejectsUnknownAliasesAndDuplicatesBeforeUpstream(t *testing.T) {
	otherRawTx := evmRawTx + "00"
	cases := []struct {
		name   string
		params string
	}{
		{
			name: "unknown field",
			params: fmt.Sprintf(
				`{"chain":"eth","payload":%q,"memo":"must-not-be-ignored"}`,
				evmRawTx,
			),
		},
		{
			name:   "case alias",
			params: fmt.Sprintf(`{"chain":"eth","Payload":%q}`, evmRawTx),
		},
		{
			name: "case alias collision",
			params: fmt.Sprintf(
				`{"chain":"eth","payload":%q,"Payload":%q}`,
				evmRawTx,
				otherRawTx,
			),
		},
		{
			name: "exact duplicate",
			params: fmt.Sprintf(
				`{"chain":"eth","payload":%q,"payload":%q}`,
				evmRawTx,
				otherRawTx,
			),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			node := newRPCFake(t)
			node.result("eth_sendRawTransaction", "0xmust-not-be-used")
			e := newEnv(t, func(cfg *handlers.Config) {
				cfg.EthURLs = []string{node.srv.URL}
			})

			resp := e.rpc("kt_broadcast", tc.params)
			errObj, ok := resp["error"].(map[string]any)
			code, codeOK := errObj["code"].(float64)
			if !ok || !codeOK || int(code) != rpc.CodeInvalidParams {
				t.Errorf("ambiguous broadcast params must be invalid, got %v", resp)
			}
			if calls := node.count("eth_sendRawTransaction"); calls != 0 {
				t.Errorf("ambiguous broadcast params reached upstream %d time(s)", calls)
			}
			if metrics := e.gw.Metrics(); !strings.Contains(
				metrics,
				`kt_gateway_broadcast_guard_operations_total{outcome="claim_acquired"} 0`,
			) {
				t.Errorf("ambiguous broadcast params reached the idempotency guard:\n%s", metrics)
			}
		})
	}
}

func TestBroadcastTronDuplicateJSONKeysNeverHitUpstream(t *testing.T) {
	cases := []struct {
		name    string
		payload string
	}{
		{
			name: "top-level duplicate",
			payload: `{"raw_data":{"contract":[{"type":"TransferContract"}]},` +
				`"signature":["ab12"],"txID":"first","txID":"second"}`,
		},
		{
			name: "nested duplicate",
			payload: `{"raw_data":{"expiration":1,"expiration":2,` +
				`"contract":[{"type":"TransferContract"}]},` +
				`"signature":["ab12"],"txID":"nested"}`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			grid := newRESTFake(t)
			grid.routeJSON("/wallet/broadcasttransaction", `{"result":true,"txid":"must-not-be-used"}`)
			e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })

			resp := e.rpc(
				"kt_broadcast",
				fmt.Sprintf(`{"chain":"tron","payload":%q}`, tc.payload),
			)
			errObj, ok := resp["error"].(map[string]any)
			code, codeOK := errObj["code"].(float64)
			if !ok || !codeOK || int(code) != rpc.CodeInvalidParams {
				t.Errorf("duplicate TRON payload keys must be invalid, got %v", resp)
			}
			if calls := len(grid.hitsFor("/wallet/broadcasttransaction")); calls != 0 {
				t.Errorf("duplicate TRON payload keys reached upstream %d time(s)", calls)
			}
		})
	}
}

func TestBroadcastDuplicateReturnsStoredResultWithoutSecondUpstreamWrite(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xhash")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)
	assertJSONEq(t, `{"txHash":"0xhash"}`, result(t, e.rpc("kt_broadcast", p)))
	assertJSONEq(t, `{"txHash":"0xhash"}`, result(t, e.rpc("kt_broadcast", p)))
	if node.count("eth_sendRawTransaction") != 1 {
		t.Fatalf("same signed transaction must be submitted once, upstream calls = %d", node.count("eth_sendRawTransaction"))
	}
}

func TestBroadcastDuplicateIsDeduplicatedAcrossGatewayInstances(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xclusterhash")
	store := newAtomicMemoryStore()
	configure := func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.BroadcastStore = store
	}
	first := newEnv(t, configure)
	second := newEnv(t, configure)
	p := fmt.Sprintf(`{"chain":"eth","network":"eth-mainnet","payload":%q}`, evmRawTx)

	assertJSONEq(t, `{"txHash":"0xclusterhash"}`, result(t, first.rpc("kt_broadcast", p)))
	assertJSONEq(t, `{"txHash":"0xclusterhash"}`, result(t, second.rpc("kt_broadcast", p)))
	if node.count("eth_sendRawTransaction") != 1 {
		t.Fatalf("cross-instance replay reached upstream %d times", node.count("eth_sendRawTransaction"))
	}
	if strings.Contains(store.lastKey(), evmRawTx) {
		t.Fatal("broadcast idempotency key leaked signed payload")
	}
	if metrics := first.gw.Metrics(); !strings.Contains(metrics, `kt_gateway_broadcast_guard_enabled 1`) ||
		!strings.Contains(metrics, `kt_gateway_broadcast_guard_operations_total{outcome="claim_acquired"} 1`) {
		t.Fatalf("first instance did not expose its acquired claim:\n%s", metrics)
	}
	if metrics := second.gw.Metrics(); !strings.Contains(metrics, `kt_gateway_broadcast_guard_operations_total{outcome="replay_accepted"} 1`) {
		t.Fatalf("second instance did not expose the accepted replay:\n%s", metrics)
	}
}

func TestBroadcastConcurrentDuplicateReturnsUnknownWithoutSecondWrite(t *testing.T) {
	node := newRPCFake(t)
	entered := make(chan struct{})
	release := make(chan struct{})
	node.handle("eth_sendRawTransaction", func([]json.RawMessage) (any, map[string]any) {
		close(entered)
		<-release
		return "0xafterwait", nil
	})
	store := newAtomicMemoryStore()
	configure := func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.BroadcastStore = store
	}
	first := newEnv(t, configure)
	second := newEnv(t, configure)
	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)

	firstDone := make(chan map[string]any, 1)
	go func() { firstDone <- first.rpc("kt_broadcast", p) }()
	<-entered
	assertErrCode(t, second.rpc("kt_broadcast", p), rpc.CodeSubmissionUnknown)
	if node.count("eth_sendRawTransaction") != 1 {
		t.Fatalf("concurrent replay reached upstream %d times", node.count("eth_sendRawTransaction"))
	}
	close(release)
	assertJSONEq(t, `{"txHash":"0xafterwait"}`, result(t, <-firstDone))
}

func TestBroadcastGuardFailureIsFailClosedBeforeUpstream(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xmust-not-be-used")
	store := newAtomicMemoryStore()
	store.err = errors.New("redis offline")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.BroadcastStore = store
	})

	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)
	assertErrCode(t, e.rpc("kt_broadcast", p), rpc.CodeSubmissionUnknown)
	if node.count("eth_sendRawTransaction") != 0 {
		t.Fatal("broadcast reached upstream without an idempotency claim")
	}
	if metrics := e.gw.Metrics(); !strings.Contains(metrics, `kt_gateway_broadcast_guard_operations_total{outcome="unavailable"} 1`) {
		t.Fatalf("guard outage was not observable:\n%s", metrics)
	}
}

func TestBroadcastCorruptAcceptedClaimFailsClosedWithoutReturningEmptyHash(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xfirsthash")
	store := newAtomicMemoryStore()
	configure := func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.BroadcastStore = store
	}
	first := newEnv(t, configure)
	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)
	assertJSONEq(t, `{"txHash":"0xfirsthash"}`, result(t, first.rpc("kt_broadcast", p)))

	store.corruptLast([]byte(`{"state":"accepted"}`))
	second := newEnv(t, configure)
	assertErrCode(t, second.rpc("kt_broadcast", p), rpc.CodeSubmissionUnknown)
	if node.count("eth_sendRawTransaction") != 1 {
		t.Fatalf("corrupt shared claim must fail closed, calls=%d", node.count("eth_sendRawTransaction"))
	}
	if metrics := second.gw.Metrics(); !strings.Contains(metrics, `kt_gateway_broadcast_guard_operations_total{outcome="corrupt_record"} 1`) {
		t.Fatalf("corrupt shared claim was not observable:\n%s", metrics)
	}
}

func TestBroadcastClaimWithMismatchedErrorCodeFailsClosed(t *testing.T) {
	node := newRPCFake(t)
	node.nodeError("eth_sendRawTransaction", -32000, "nonce too low")
	store := newAtomicMemoryStore()
	configure := func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.BroadcastStore = store
	}
	first := newEnv(t, configure)
	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)
	assertErrCode(t, first.rpc("kt_broadcast", p), rpc.CodeUpstream)

	store.corruptLast([]byte(`{"state":"rejected","error":{"code":-32003,"message":"submission_unknown"}}`))
	second := newEnv(t, configure)
	assertErrCode(t, second.rpc("kt_broadcast", p), rpc.CodeSubmissionUnknown)
	if node.count("eth_sendRawTransaction") != 1 {
		t.Fatalf("invalid shared error record must fail closed, calls=%d", node.count("eth_sendRawTransaction"))
	}
}

func TestBroadcastResultPersistenceFailureIsObservable(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xaccepted")
	store := newAtomicMemoryStore()
	store.setErr = errors.New("redis result write failed")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.BroadcastStore = store
	})
	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)

	assertJSONEq(t, `{"txHash":"0xaccepted"}`, result(t, e.rpc("kt_broadcast", p)))
	if node.count("eth_sendRawTransaction") != 1 {
		t.Fatalf("accepted transaction was submitted %d times", node.count("eth_sendRawTransaction"))
	}
	if metrics := e.gw.Metrics(); !strings.Contains(metrics, `kt_gateway_broadcast_guard_operations_total{outcome="persist_error"} 1`) {
		t.Fatalf("terminal-result persistence failure was not observable:\n%s", metrics)
	}
}

func TestBroadcastFingerprintCanonicalizesEquivalentPayloads(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xhash")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	lower := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)
	upperPayload := "0x" + strings.ToUpper(strings.TrimPrefix(evmRawTx, "0x"))
	upper := fmt.Sprintf(`{"chain":"eth","payload":%q}`, upperPayload)
	result(t, e.rpc("kt_broadcast", lower))
	result(t, e.rpc("kt_broadcast", upper))
	if node.count("eth_sendRawTransaction") != 1 {
		t.Fatalf("equivalent hex payloads must share one claim, calls=%d", node.count("eth_sendRawTransaction"))
	}
}

func TestBroadcastRejectedResultIsReplayedWithoutSecondWrite(t *testing.T) {
	node := newRPCFake(t)
	node.nodeError("eth_sendRawTransaction", -32000, "nonce too low")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })
	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)

	assertErrCode(t, e.rpc("kt_broadcast", p), rpc.CodeUpstream)
	assertErrCode(t, e.rpc("kt_broadcast", p), rpc.CodeUpstream)
	if node.count("eth_sendRawTransaction") != 1 {
		t.Fatalf("explicit rejection replay reached upstream %d times", node.count("eth_sendRawTransaction"))
	}
}

func TestBroadcastUnknownResultIsReplayedWithoutSecondWrite(t *testing.T) {
	var hits atomic.Int32
	node := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		http.Error(w, "lost response", http.StatusBadGateway)
	}))
	t.Cleanup(node.Close)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.URL} })
	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)

	assertErrCode(t, e.rpc("kt_broadcast", p), rpc.CodeSubmissionUnknown)
	assertErrCode(t, e.rpc("kt_broadcast", p), rpc.CodeSubmissionUnknown)
	if hits.Load() != 1 {
		t.Fatalf("unknown-result replay reached upstream %d times", hits.Load())
	}
}

func TestBroadcastSamePayloadOnDifferentNetworksUsesDistinctClaims(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xhash")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.EthSepoliaURLs = []string{node.srv.URL}
	})

	mainnet := fmt.Sprintf(`{"chain":"eth","network":"eth-mainnet","payload":%q}`, evmRawTx)
	sepolia := fmt.Sprintf(`{"chain":"eth","network":"eth-sepolia","payload":%q}`, evmRawTx)
	result(t, e.rpc("kt_broadcast", mainnet))
	result(t, e.rpc("kt_broadcast", sepolia))
	if node.count("eth_sendRawTransaction") != 2 {
		t.Fatalf("network identity must scope broadcast claims, calls=%d", node.count("eth_sendRawTransaction"))
	}
}

func TestBroadcastTronCanonicalJSONDeduplicatesFieldOrder(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON("/wallet/broadcasttransaction", `{"result":true,"txid":"deadbeef"}`)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })
	first := `{"chain":"tron","payload":"{\"txID\":\"deadbeef\",\"signature\":[\"ab12\"],\"raw_data\":{\"contract\":[{\"type\":\"TransferContract\"}]}}"}`
	second := `{"chain":"tron","payload":"{\"raw_data\":{\"contract\":[{\"type\":\"TransferContract\"}]},\"signature\":[\"ab12\"],\"txID\":\"deadbeef\"}"}`

	result(t, e.rpc("kt_broadcast", first))
	result(t, e.rpc("kt_broadcast", second))
	if hits := grid.hitsFor("/wallet/broadcasttransaction"); len(hits) != 1 {
		t.Fatalf("equivalent TRON JSON reached upstream %d times", len(hits))
	}
}

func TestBroadcastTronFingerprintPreservesLargeIntegerPrecision(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON("/wallet/broadcasttransaction", `{"result":true,"txid":"deadbeef"}`)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.TronURL = grid.srv.URL })
	firstPayload := `{"raw_data":{"amount":9007199254740992},"signature":["ab12"],"txID":"same-label"}`
	secondPayload := `{"raw_data":{"amount":9007199254740993},"signature":["ab12"],"txID":"same-label"}`
	first := fmt.Sprintf(`{"chain":"tron","payload":%q}`, firstPayload)
	second := fmt.Sprintf(`{"chain":"tron","payload":%q}`, secondPayload)

	result(t, e.rpc("kt_broadcast", first))
	result(t, e.rpc("kt_broadcast", second))
	if hits := grid.hitsFor("/wallet/broadcasttransaction"); len(hits) != 2 {
		t.Fatalf("distinct 64-bit TRON values shared a claim, calls=%d", len(hits))
	}
}

func TestBroadcastInvalidChain(t *testing.T) {
	e := newEnv(t, nil)
	assertErrCode(t, e.rpc("kt_broadcast", `{"chain":"btc","payload":"0xab"}`), rpc.CodeInvalidParams)
}

type atomicMemoryStore struct {
	mu     sync.Mutex
	values map[string][]byte
	last   string
	err    error
	setErr error
}

func newAtomicMemoryStore() *atomicMemoryStore {
	return &atomicMemoryStore{values: make(map[string][]byte)}
}

func (s *atomicMemoryStore) Get(_ context.Context, key string) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.last = key
	if s.err != nil {
		return nil, s.err
	}
	value, ok := s.values[key]
	if !ok {
		return nil, errors.New("not found")
	}
	return append([]byte(nil), value...), nil
}

func (s *atomicMemoryStore) Set(
	_ context.Context,
	key string,
	value []byte,
	_ time.Duration,
) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.last = key
	if s.err != nil {
		return s.err
	}
	if s.setErr != nil {
		return s.setErr
	}
	s.values[key] = append([]byte(nil), value...)
	return nil
}

func (s *atomicMemoryStore) SetNX(
	_ context.Context,
	key string,
	value []byte,
	_ time.Duration,
) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.last = key
	if s.err != nil {
		return false, s.err
	}
	if _, exists := s.values[key]; exists {
		return false, nil
	}
	s.values[key] = append([]byte(nil), value...)
	return true, nil
}

func (s *atomicMemoryStore) lastKey() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.last
}

func (s *atomicMemoryStore) corruptLast(value []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.values[s.last] = append([]byte(nil), value...)
}

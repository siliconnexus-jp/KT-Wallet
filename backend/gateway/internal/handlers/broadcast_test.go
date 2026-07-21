package handlers_test

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"testing"

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

func TestBroadcastEVMNodeRejection(t *testing.T) {
	node := newRPCFake(t)
	node.nodeError("eth_sendRawTransaction", -32000, "nonce too low")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	if errObj["message"] != "nonce too low" {
		t.Fatalf("node's message must surface, got %q", errObj["message"])
	}
	if d := errData(t, errObj); d["message"] != "nonce too low" {
		t.Fatalf("data.message must carry the node's message, got %v", d)
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
	if msg != "SIGERROR: Validate signature error" {
		t.Fatalf("tron rejection should decode the hex message, got %q", msg)
	}
}

func TestBroadcastSolanaNodeRejection(t *testing.T) {
	node := newRPCFake(t)
	node.nodeError("sendTransaction", -32002, "Transaction simulation failed: Blockhash not found")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.SolanaURLs = []string{node.srv.URL} })

	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"solana","payload":%q}`, solRawTx))
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	if errObj["message"] != "Transaction simulation failed: Blockhash not found" {
		t.Fatalf("node message lost: %v", errObj["message"])
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

func TestBroadcastNeverCached(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", "0xhash")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	p := fmt.Sprintf(`{"chain":"eth","payload":%q}`, evmRawTx)
	result(t, e.rpc("kt_broadcast", p))
	result(t, e.rpc("kt_broadcast", p))
	if node.count("eth_sendRawTransaction") != 2 {
		t.Fatalf("broadcast must never be cached, upstream calls = %d", node.count("eth_sendRawTransaction"))
	}
}

func TestBroadcastInvalidChain(t *testing.T) {
	e := newEnv(t, nil)
	assertErrCode(t, e.rpc("kt_broadcast", `{"chain":"btc","payload":"0xab"}`), rpc.CodeInvalidParams)
}

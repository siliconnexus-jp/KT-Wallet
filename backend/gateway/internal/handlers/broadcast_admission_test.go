package handlers_test

import (
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

// Complete, distinct envelopes with mock signatures. Only local fake nodes
// are configured in these tests; no real transaction or money is involved.
func mockSignedPayload(i int) string {
	r := make([]byte, 32)
	r[0] = 1
	binary.BigEndian.PutUint32(r[28:], uint32(i))
	return "0x02f842018001028252089411111111111111111111111111111111111111110180c080a0" + hex.EncodeToString(r) + "01"
}

func TestBroadcastMalformedFloodNeverClaimsCapacity(t *testing.T) {
	base := newRPCFake(t)
	base.result("eth_sendRawTransaction", evmBroadcastHash)
	e := newEnv(t, func(cfg *handlers.Config) { cfg.BaseURLs = []string{base.srv.URL} })
	for i := 0; i < 4096; i++ {
		resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"eth","payload":"0x%04x"}`, i))
		assertErrCode(t, resp, rpc.CodeInvalidParams)
		e.clk.Advance(100 * time.Millisecond)
	}
	if !strings.Contains(e.gw.Metrics(), `kt_gateway_broadcast_guard_operations_total{outcome="claim_acquired"} 0`) {
		t.Fatal("malformed transactions consumed claims")
	}
	resp := e.rpc("kt_broadcast", fmt.Sprintf(`{"chain":"base","payload":%q}`, evmRawTx))
	assertBoundBroadcastResult(t, resp, "base", "base-mainnet", evmBroadcastHash)
}

func TestBroadcastFramedRejectionsDoNotBlockLegitimateTraffic(t *testing.T) {
	for _, shared := range []bool{false, true} {
		t.Run(fmt.Sprint("shared=", shared), func(t *testing.T) {
			eth, base := newRPCFake(t), newRPCFake(t)
			eth.nodeError("eth_sendRawTransaction", -32000, "invalid signature")
			base.result("eth_sendRawTransaction", evmBroadcastHash)
			e := newEnv(t, func(cfg *handlers.Config) {
				cfg.EthURLs, cfg.BaseURLs = []string{eth.srv.URL}, []string{base.srv.URL}
				if shared {
					cfg.BroadcastStore = newAtomicMemoryStore()
				}
			})
			for i := 0; i < 4100; i++ {
				resp := e.rpc("kt_broadcast", map[string]string{"chain": "eth", "payload": mockSignedPayload(i)})
				assertErrCode(t, resp, rpc.CodeUpstream)
			}
			resp := e.rpc("kt_broadcast", map[string]string{"chain": "base", "payload": evmRawTx})
			assertBoundBroadcastResult(t, resp, "base", "base-mainnet", evmBroadcastHash)
		})
	}
}

func TestBroadcastSharedAcceptedEvictionStillDeduplicatesUpstream(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_sendRawTransaction", evmBroadcastHash)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
		cfg.BroadcastStore = newAtomicMemoryStore()
	})
	for i := 0; i < 4100; i++ {
		resp := e.rpc("kt_broadcast", map[string]string{"chain": "eth", "payload": mockSignedPayload(i)})
		assertBoundBroadcastResult(t, resp, "eth", "eth-mainnet", evmBroadcastHash)
	}
	resp := e.rpc("kt_broadcast", map[string]string{"chain": "eth", "payload": mockSignedPayload(0)})
	assertBoundBroadcastResult(t, resp, "eth", "eth-mainnet", evmBroadcastHash)
	if node.count("eth_sendRawTransaction") != 4100 {
		t.Fatal("cache eviction repeated an upstream write")
	}
}

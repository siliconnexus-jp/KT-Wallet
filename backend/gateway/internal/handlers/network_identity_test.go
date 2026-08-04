package handlers_test

import (
	"testing"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

func TestEVMNetworkIdentityUsesLiveChainID(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_chainId", "0x1")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc(
		"kt_getNetworkIdentity",
		`{"chain":"eth","network":"eth-mainnet"}`,
	))
	if res["network"] != "eth-mainnet" || res["identity"] != "1" {
		t.Fatalf("unexpected identity response: %v", res)
	}
	if node.count("eth_chainId") != 1 {
		t.Fatalf("expected one live chain-id call, got %d", node.count("eth_chainId"))
	}
}

func TestNetworkIdentityRejectsMisroutedEVMUpstream(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_chainId", "0x2")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})

	assertErrCode(t, e.rpc(
		"kt_getNetworkIdentity",
		`{"chain":"eth","network":"eth-mainnet"}`,
	), rpc.CodeUpstream)
}

func TestSolanaNetworkIdentityUsesLiveGenesisHash(t *testing.T) {
	const genesis = "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG"
	node := newRPCFake(t)
	node.result("getGenesisHash", genesis)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.SolanaDevnetURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc(
		"kt_getNetworkIdentity",
		`{"chain":"solana","network":"sol-devnet"}`,
	))
	if res["network"] != "sol-devnet" || res["identity"] != genesis {
		t.Fatalf("unexpected identity response: %v", res)
	}
}

func TestTronNetworkIdentityUsesLiveBlockZero(t *testing.T) {
	const genesis = "0000000000000000d698d4192c56cb6be724a558448e2684802de4d6cd8690dc"
	grid := newRESTFake(t)
	grid.routeJSON(
		"/wallet/getblockbynum",
		`{"blockID":"`+genesis+`","block_header":{"raw_data":{"number":0}}}`,
	)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TronNileURL = grid.srv.URL
	})

	res := result(t, e.rpc(
		"kt_getNetworkIdentity",
		`{"chain":"tron","network":"tron-nile"}`,
	))
	if res["network"] != "tron-nile" || res["identity"] != genesis {
		t.Fatalf("unexpected identity response: %v", res)
	}
	hits := grid.hitsFor("/wallet/getblockbynum")
	if len(hits) != 1 || hits[0].Body != `{"num":0}` {
		t.Fatalf("unexpected block-zero request: %+v", hits)
	}
}

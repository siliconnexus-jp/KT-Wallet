package handlers_test

import (
	"fmt"
	"net/url"
	"strings"
	"testing"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

// The EVM families added alongside eth/polygon. Before they existed every
// kt_* call from a Base/Arbitrum/Avalanche wallet answered -32602 and the app
// fell back to its direct path after a wasted round trip.
type evmFamily struct {
	chain    string
	mainnet  string // network id
	testnet  string // network id
	symbol   string
	mainID   string // Etherscan v2 chainid, mainnet
	testID   string // Etherscan v2 chainid, testnet
	setPools func(cfg *handlers.Config, mainnetURL, testnetURL string)
}

var newEVMFamilies = []evmFamily{
	{
		chain: "base", mainnet: "base-mainnet", testnet: "base-sepolia",
		symbol: "ETH", mainID: "8453", testID: "84532",
		setPools: func(cfg *handlers.Config, m, t string) {
			cfg.BaseURLs, cfg.BaseSepoliaURLs = []string{m}, []string{t}
		},
	},
	{
		chain: "arbitrum", mainnet: "arbitrum-mainnet", testnet: "arbitrum-sepolia",
		symbol: "ETH", mainID: "42161", testID: "421614",
		setPools: func(cfg *handlers.Config, m, t string) {
			cfg.ArbitrumURLs, cfg.ArbitrumSepoliaURLs = []string{m}, []string{t}
		},
	},
	{
		chain: "avalanche", mainnet: "avalanche-mainnet", testnet: "avalanche-fuji",
		symbol: "AVAX", mainID: "43114", testID: "43113",
		setPools: func(cfg *handlers.Config, m, t string) {
			cfg.AvalancheURLs, cfg.AvalancheFujiURLs = []string{m}, []string{t}
		},
	},
	{
		chain: "bnb", mainnet: "bnb-mainnet", testnet: "bnb-testnet",
		symbol: "BNB", mainID: "56", testID: "97",
		setPools: func(cfg *handlers.Config, m, t string) {
			cfg.BNBURLs, cfg.BNBTestnetURLs = []string{m}, []string{t}
		},
	},
}

// newFamilyEnv wires one fake node per network of fam so a test can prove
// which network an upstream call landed on.
func newFamilyEnv(t *testing.T, fam evmFamily) (mainnet, testnet *rpcFake, e *env) {
	t.Helper()
	mainnet, testnet = newRPCFake(t), newRPCFake(t)
	e = newEnv(t, func(cfg *handlers.Config) {
		fam.setPools(cfg, mainnet.srv.URL, testnet.srv.URL)
	})
	return mainnet, testnet, e
}

func TestNewEVMFamilyBalances(t *testing.T) {
	for _, fam := range newEVMFamilies {
		t.Run(fam.chain, func(t *testing.T) {
			mainnet, testnet, e := newFamilyEnv(t, fam)
			mainnet.result("eth_getBalance", "0x1")
			testnet.result("eth_getBalance", "0x2")

			// Omitted network → the family's mainnet.
			res := result(t, e.rpc("kt_getBalances", balancesParams(fam.chain, evmSelf, "")))
			assertJSONEq(t, fmt.Sprintf(`{"raw":"1","decimals":18,"symbol":%q}`, fam.symbol), res["native"])
			if mainnet.count("eth_getBalance") != 1 || testnet.totalCalls() != 0 {
				t.Fatalf("omitted network must hit mainnet only (main=%d, test=%d)",
					mainnet.count("eth_getBalance"), testnet.totalCalls())
			}

			// Explicit testnet → the testnet pool, never mainnet.
			res = result(t, e.rpc("kt_getBalances",
				fmt.Sprintf(`{"chain":%q,"network":%q,"address":%q}`, fam.chain, fam.testnet, evmSelf)))
			if raw := res["native"].(map[string]any)["raw"]; raw != "2" {
				t.Fatalf("%s must answer from its own upstream, got %v", fam.testnet, raw)
			}
			if mainnet.count("eth_getBalance") != 1 {
				t.Fatalf("a testnet request must never touch the mainnet pool, mainnet fetches = %d",
					mainnet.count("eth_getBalance"))
			}
		})
	}
}

func TestNewEVMFamilyCacheIsolatedPerNetwork(t *testing.T) {
	for _, fam := range newEVMFamilies {
		t.Run(fam.chain, func(t *testing.T) {
			mainnet, testnet, e := newFamilyEnv(t, fam)
			mainnet.result("eth_getBalance", "0x1")
			testnet.result("eth_getBalance", "0x2")

			pMain := fmt.Sprintf(`{"chain":%q,"network":%q,"address":%q}`, fam.chain, fam.mainnet, evmSelf)
			pTest := fmt.Sprintf(`{"chain":%q,"network":%q,"address":%q}`, fam.chain, fam.testnet, evmSelf)
			for range 2 {
				if raw := result(t, e.rpc("kt_getBalances", pMain))["native"].(map[string]any)["raw"]; raw != "1" {
					t.Fatalf("mainnet raw = %v", raw)
				}
				if raw := result(t, e.rpc("kt_getBalances", pTest))["native"].(map[string]any)["raw"]; raw != "2" {
					t.Fatalf("testnet raw = %v (a mainnet answer must never be recycled)", raw)
				}
			}
			if mainnet.count("eth_getBalance") != 1 || testnet.count("eth_getBalance") != 1 {
				t.Fatalf("each network caches independently (main=%d, test=%d)",
					mainnet.count("eth_getBalance"), testnet.count("eth_getBalance"))
			}
		})
	}
}

func TestNewEVMFamilyChainParamsAndBroadcast(t *testing.T) {
	for _, fam := range newEVMFamilies {
		t.Run(fam.chain, func(t *testing.T) {
			mainnet, testnet, e := newFamilyEnv(t, fam)
			testnet.result("eth_getTransactionCount", "0x5")
			testnet.nodeError("eth_feeHistory", -32601, "method not found") // gasPrice fallback
			testnet.result("eth_gasPrice", "0x64")
			testnet.result("eth_sendRawTransaction", "0xtestnethash")

			res := result(t, e.rpc("kt_getChainParams",
				fmt.Sprintf(`{"chain":%q,"network":%q,"address":%q}`, fam.chain, fam.testnet, evmSelf)))
			if res["nonce"] != "5" {
				t.Fatalf("nonce must come from the %s node, got %v", fam.testnet, res["nonce"])
			}

			resp := e.rpc("kt_broadcast",
				fmt.Sprintf(`{"chain":%q,"network":%q,"payload":%q}`, fam.chain, fam.testnet, evmRawTx))
			assertJSONEq(t, `{"txHash":"0xtestnethash"}`, result(t, resp))

			if mainnet.totalCalls() != 0 {
				t.Fatalf("a %s transaction must never reach the mainnet node, saw %d calls",
					fam.testnet, mainnet.totalCalls())
			}
		})
	}
}

func TestNewEVMFamilyHistoryUsesEtherscanChainID(t *testing.T) {
	for _, fam := range newEVMFamilies {
		t.Run(fam.chain, func(t *testing.T) {
			scan := newRESTFake(t)
			scan.routeJSON("/", `{"status":"1","message":"OK","result":[]}`)
			e := newEnv(t, func(cfg *handlers.Config) {
				cfg.EtherscanURL = scan.srv.URL
				cfg.EtherscanKey = "k"
			})

			for network, wantChainID := range map[string]string{
				fam.mainnet: fam.mainID,
				fam.testnet: fam.testID,
			} {
				res := result(t, e.rpc("kt_getHistory",
					fmt.Sprintf(`{"chain":%q,"network":%q,"address":%q}`, fam.chain, network, evmSelf)))
				if res["status"] != "ok" {
					t.Fatalf("%s: status = %v", network, res["status"])
				}
				hits := scan.hitsFor("/")
				u, _ := url.Parse(hits[len(hits)-1].Path)
				if got := u.Query().Get("chainid"); got != wantChainID {
					t.Fatalf("%s must query chainid=%s, got %q", network, wantChainID, got)
				}
			}
		})
	}
}

func TestNewEVMFamilyNetworkMismatchRejected(t *testing.T) {
	node := newRPCFake(t) // must never be called
	e := newEnv(t, func(cfg *handlers.Config) {
		for _, fam := range newEVMFamilies {
			fam.setPools(cfg, node.srv.URL, node.srv.URL)
		}
		cfg.EthURLs = []string{node.srv.URL}
	})

	// A network id from another family (or a plausible-looking invention) must
	// be a -32602, never a silent fall-through to the family's mainnet.
	for _, call := range []struct{ chain, network string }{
		{"base", "arbitrum-mainnet"},
		{"base", "eth-sepolia"},
		{"arbitrum", "base-sepolia"},
		{"arbitrum", "avalanche-fuji"},
		{"avalanche", "polygon-amoy"},
		{"eth", "base-mainnet"},
		{"base", "base-goerli"},    // no such network
		{"avalanche", "avalanche"}, // a family name is not a network id
	} {
		params := fmt.Sprintf(`{"chain":%q,"network":%q,"address":%q}`, call.chain, call.network, evmSelf)
		errObj := assertErrCode(t, e.rpc("kt_getBalances", params), rpc.CodeInvalidParams)
		if msg, _ := errObj["message"].(string); !strings.Contains(msg, `"network"`) {
			t.Fatalf("%s/%s: error must name the network field, got %q", call.chain, call.network, msg)
		}
	}
	if node.totalCalls() != 0 {
		t.Fatalf("a rejected chain/network pair must never reach an upstream, saw %d calls", node.totalCalls())
	}
}

// The chain list in the -32602 message is generated from the registry, so a
// newly added family can never be missing from it.
func TestChainErrorMessageListsEveryFamily(t *testing.T) {
	e := newEnv(t, nil)
	errObj := assertErrCode(t,
		e.rpc("kt_getBalances", fmt.Sprintf(`{"chain":"dogecoin","address":%q}`, evmSelf)),
		rpc.CodeInvalidParams)
	msg, _ := errObj["message"].(string)
	for _, chain := range []string{"eth", "polygon", "base", "arbitrum", "avalanche", "tron", "solana"} {
		if !strings.Contains(msg, `"`+chain+`"`) {
			t.Fatalf("chain error message must list %q, got %q", chain, msg)
		}
	}
}

package handlers_test

import (
	"encoding/json"
	"fmt"
	"reflect"
	"testing"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

func TestEVMPreflightForwardsExactPendingCall(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_call", "0x"+fmt.Sprintf("%064x", 1))
	node.result("eth_estimateGas", "0x5208")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.PolygonAmoyURLs = []string{node.srv.URL}
	})
	params := map[string]any{
		"chain":   "polygon",
		"network": "polygon-amoy",
		"from":    evmSelf,
		"to":      evmTokenA,
		"value":   "15",
		"data":    "0xA9059CBB",
	}

	simulated := result(t, e.rpc("kt_simulateEvmTransfer", params))
	if simulated["returnData"] != "0x"+fmt.Sprintf("%064x", 1) {
		t.Fatalf("returnData = %v", simulated["returnData"])
	}
	gas := result(t, e.rpc("kt_estimateEvmGas", params))
	if gas["gas"] != "21000" {
		t.Fatalf("gas = %v, want decimal 21000", gas["gas"])
	}

	for _, method := range []string{"eth_call", "eth_estimateGas"} {
		got := node.params(method)
		if len(got) != 2 || string(got[1]) != `"pending"` {
			t.Fatalf("%s params = %s, want transaction + pending", method, got)
		}
		var call map[string]string
		if err := json.Unmarshal(got[0], &call); err != nil {
			t.Fatal(err)
		}
		want := map[string]string{
			"from":  evmSelf,
			"to":    evmTokenA,
			"value": "0xf",
			"data":  "0xa9059cbb",
		}
		assertJSONEq(t, `{"from":"`+evmSelf+`","to":"`+evmTokenA+`","value":"0xf","data":"0xa9059cbb"}`, call)
		if len(call) != len(want) {
			t.Fatalf("%s call has unexpected fields: %v", method, call)
		}
	}
}

func TestEVMPreflightAllowsLatestForSameNonceReplacement(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_call", "0x")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.AvalancheFujiURLs = []string{node.srv.URL}
	})
	params := map[string]any{
		"chain":    "avalanche",
		"network":  "avalanche-fuji",
		"from":     evmSelf,
		"to":       evmSelf,
		"value":    "0",
		"data":     "0x",
		"blockTag": "latest",
	}

	result(t, e.rpc("kt_simulateEvmTransfer", params))
	got := node.params("eth_call")
	if len(got) != 2 || string(got[1]) != `"latest"` {
		t.Fatalf("eth_call params = %s, want transaction + latest", got)
	}
}

func TestEVMPreflightRevertPropagatesAndIsNotCached(t *testing.T) {
	node := newRPCFake(t)
	node.nodeError("eth_call", 3, "execution reverted: insufficient balance")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})
	params := fmt.Sprintf(
		`{"chain":"eth","from":%q,"to":%q,"value":"0","data":"0x"}`,
		evmSelf,
		evmTokenA,
	)

	for range 2 {
		err := assertErrCode(t, e.rpc("kt_simulateEvmTransfer", params), rpc.CodeUpstream)
		if err["message"] != "transaction execution reverted" {
			t.Fatalf("message = %v", err["message"])
		}
	}
	if node.count("eth_call") != 2 {
		t.Fatalf("state-dependent simulation must not be cached, calls=%d", node.count("eth_call"))
	}
}

func TestEVMPreflightRejectsUnsafeOrWrongNetworkParams(t *testing.T) {
	e := newEnv(t, nil)
	cases := []string{
		fmt.Sprintf(`{"chain":"tron","from":%q,"to":%q,"value":"0","data":"0x"}`, evmSelf, evmTokenA),
		fmt.Sprintf(`{"chain":"eth","network":"polygon-amoy","from":%q,"to":%q,"value":"0","data":"0x"}`, evmSelf, evmTokenA),
		fmt.Sprintf(`{"chain":"eth","from":"0x1","to":%q,"value":"0","data":"0x"}`, evmTokenA),
		fmt.Sprintf(`{"chain":"eth","from":%q,"to":%q,"value":"-1","data":"0x"}`, evmSelf, evmTokenA),
		fmt.Sprintf(`{"chain":"eth","from":%q,"to":%q,"value":"0","data":"0x0"}`, evmSelf, evmTokenA),
		fmt.Sprintf(`{"chain":"eth","from":%q,"to":%q,"value":"0","data":"0xzz"}`, evmSelf, evmTokenA),
		fmt.Sprintf(`{"chain":"eth","from":%q,"to":%q,"value":"0","data":"0x","blockTag":"safe"}`, evmSelf, evmTokenA),
	}
	for _, params := range cases {
		assertErrCode(t, e.rpc("kt_simulateEvmTransfer", params), rpc.CodeInvalidParams)
		assertErrCode(t, e.rpc("kt_estimateEvmGas", params), rpc.CodeInvalidParams)
	}
}

func TestEVMSpendableBalancesReadPendingStateWithoutCache(t *testing.T) {
	node := newRPCFake(t)
	var balanceTags []string
	node.handle("eth_getBalance", func(params []json.RawMessage) (any, map[string]any) {
		if len(params) == 2 {
			var tag string
			_ = json.Unmarshal(params[1], &tag)
			balanceTags = append(balanceTags, tag)
		}
		return "0xde0b6b3a7640000", nil
	})
	node.result("eth_call", "0x0000000000000000000000000000000000000000000000000000000005f5e100")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})
	params := map[string]any{
		"chain":         "eth",
		"address":       evmSelf,
		"tokenContract": evmTokenA,
	}

	for range 2 {
		got := result(t, e.rpc("kt_getEvmSpendableBalances", params))
		assertJSONEq(t, `{"native":"1000000000000000000","nativeLatest":"1000000000000000000","nativePending":"1000000000000000000","pendingAvailable":true,"token":"100000000"}`, got)
	}
	if node.count("eth_getBalance") != 4 || node.count("eth_call") != 2 {
		t.Fatalf(
			"spendable balances must not be cached: native=%d token=%d",
			node.count("eth_getBalance"),
			node.count("eth_call"),
		)
	}
	wantTags := []string{"latest", "pending", "latest", "pending"}
	if !reflect.DeepEqual(balanceTags, wantTags) {
		t.Fatalf("eth_getBalance tags = %v, want %v", balanceTags, wantTags)
	}
	if got := node.params("eth_call"); len(got) != 2 || string(got[1]) != `"pending"` {
		t.Fatalf("balanceOf params = %s", got)
	}
}

func TestEVMSpendableBalancesMarksUnsupportedPendingState(t *testing.T) {
	node := newRPCFake(t)
	node.handle("eth_getBalance", func(params []json.RawMessage) (any, map[string]any) {
		if len(params) == 2 && string(params[1]) == `"latest"` {
			return "0xde0b6b3a7640000", nil
		}
		return nil, map[string]any{
			"code": -32000, "message": "state not available for pending block",
		}
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.AvalancheFujiURLs = []string{node.srv.URL}
	})
	params := fmt.Sprintf(
		`{"chain":"avalanche","network":"avalanche-fuji","address":%q}`,
		evmSelf,
	)

	got := result(t, e.rpc("kt_getEvmSpendableBalances", params))
	assertJSONEq(t, `{"native":"1000000000000000000","nativeLatest":"1000000000000000000","nativePending":"1000000000000000000","pendingAvailable":false}`, got)
}

func TestEVMSpendableBalancesRejectsInvalidTokenContract(t *testing.T) {
	e := newEnv(t, nil)
	params := fmt.Sprintf(
		`{"chain":"eth","address":%q,"tokenContract":"0x1"}`,
		evmSelf,
	)
	assertErrCode(
		t,
		e.rpc("kt_getEvmSpendableBalances", params),
		rpc.CodeInvalidParams,
	)
}

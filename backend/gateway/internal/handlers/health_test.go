package handlers_test

import "testing"

func TestHealthGolden(t *testing.T) {
	e := newEnv(t, nil)
	resp := e.rpc("kt_health", nil)
	assertJSONEq(t, `{"ok":true,"version":"9.9.9-test",
		"networks":["eth-mainnet","eth-sepolia","polygon-mainnet","polygon-amoy",
			"base-mainnet","base-sepolia","arbitrum-mainnet","arbitrum-sepolia",
			"avalanche-mainnet","avalanche-fuji",
			"tron-mainnet","tron-nile","sol-mainnet","sol-devnet"]}`,
		result(t, resp))
}

func TestHealthIgnoresParams(t *testing.T) {
	e := newEnv(t, nil)
	resp := e.rpc("kt_health", `{"anything":"goes"}`)
	if result(t, resp)["ok"] != true {
		t.Fatal("kt_health must succeed regardless of params")
	}
}

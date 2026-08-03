package handlers_test

import (
	"os"
	"path/filepath"
	"testing"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

func TestSearchOfficialTokensBySymbolAndContract(t *testing.T) {
	e := newEnv(t, nil)

	bySymbol := result(t, e.rpc("kt_searchTokens", `{"query":"usdt","limit":100}`))
	rows := bySymbol["tokens"].([]any)
	if len(rows) < 5 {
		t.Fatalf("USDT search should cover its configured networks: %v", rows)
	}
	for _, raw := range rows {
		row := raw.(map[string]any)
		if row["symbol"] != "USDT" || row["verified"] != true {
			t.Fatalf("search returned a non-verified/non-USDT row: %v", row)
		}
	}

	const contract = "0xdac17f958d2ee523a2206206994597c13d831ec7"
	byContract := result(t, e.rpc("kt_searchTokens", map[string]any{
		"query": contract,
	}))
	exact := byContract["tokens"].([]any)
	if len(exact) != 1 {
		t.Fatalf("exact contract search = %v, want one result", exact)
	}
	row := exact[0].(map[string]any)
	if row["network"] != "eth-mainnet" || row["contract"] != contract {
		t.Fatalf("wrong exact match: %v", row)
	}
}

func TestSearchOfficialTokensUsesOperatorCatalog(t *testing.T) {
	const contract = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.OfficialTokens = []handlers.OfficialToken{{
			Network:  "eth-mainnet",
			Symbol:   "KTT",
			Name:     "KT Test Token",
			Contract: contract,
			Decimals: 8,
			Popular:  true,
		}}
	})

	res := result(t, e.rpc("kt_searchTokens", `{"query":"KT Test"}`))
	rows := res["tokens"].([]any)
	if len(rows) != 1 {
		t.Fatalf("custom catalog search = %v", rows)
	}
	row := rows[0].(map[string]any)
	if row["symbol"] != "KTT" || row["verified"] != true {
		t.Fatalf("custom catalog row = %v", row)
	}

	noBuiltins := result(t, e.rpc("kt_searchTokens", `{"query":"USDT"}`))
	if len(noBuiltins["tokens"].([]any)) != 0 {
		t.Fatal("operator catalog must replace, not append to, the defaults")
	}
}

func TestLoadOfficialTokensFileRejectsDuplicateIdentity(t *testing.T) {
	path := filepath.Join(t.TempDir(), "official-tokens.json")
	const body = `[
		{"network":"eth-mainnet","symbol":"AAA","name":"A","contract":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","decimals":6},
		{"network":"eth-mainnet","symbol":"BBB","name":"B","contract":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","decimals":6}
	]`
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := handlers.LoadOfficialTokensFile(path); err == nil {
		t.Fatal("duplicate network + contract must fail closed")
	}
}

func TestCheckedInOfficialTokenCatalogLoads(t *testing.T) {
	tokens, err := handlers.LoadOfficialTokensFile(
		filepath.Join("..", "..", "config", "official-tokens.json"),
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(tokens) < 20 {
		t.Fatalf("checked-in catalog is unexpectedly small: %d", len(tokens))
	}
	wanted := map[string]bool{
		"DAI": false, "WETH": false, "WBTC": false, "LINK": false,
		"UNI": false, "SHIB": false, "PEPE": false, "JUP": false,
		"BONK": false, "PYUSD": false, "BUSD": false,
	}
	hasBNB := false
	hasBNBTestnetBUSD := false
	for _, token := range tokens {
		if _, ok := wanted[token.Symbol]; ok {
			wanted[token.Symbol] = true
		}
		if token.Network == "bnb-mainnet" {
			hasBNB = true
		}
		if token.Network == "bnb-testnet" &&
			token.Symbol == "BUSD" &&
			token.Contract == "0xed24fc36d5ee211ea25a80239fb8c4cfd80f12ee" {
			hasBNBTestnetBUSD = true
		}
	}
	for symbol, found := range wanted {
		if !found {
			t.Errorf("checked-in catalog is missing %s", symbol)
		}
	}
	if !hasBNB {
		t.Error("checked-in catalog is missing BNB Smart Chain")
	}
	if !hasBNBTestnetBUSD {
		t.Error("checked-in catalog is missing BNB Testnet BUSD")
	}
}

func TestSearchOfficialTokensValidatesFilters(t *testing.T) {
	e := newEnv(t, nil)
	assertErrCode(
		t,
		e.rpc("kt_searchTokens", `{"networks":["not-a-network"]}`),
		rpc.CodeInvalidParams,
	)
	assertErrCode(
		t,
		e.rpc("kt_searchTokens", `{"limit":101}`),
		rpc.CodeInvalidParams,
	)
}

func TestSearchOfficialTokensKeepsBase58ContractQueriesCaseSensitive(t *testing.T) {
	e := newEnv(t, nil)
	for _, tc := range []struct {
		network  string
		exact    string
		modified string
	}{
		{
			network:  "tron-mainnet",
			exact:    "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
			modified: "tr7nhqjekqxtci8q8zy4pl8otszgjlj6t",
		},
		{
			network:  "sol-mainnet",
			exact:    "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
			modified: "jupyiwryjfskupiha7hker8vutaefosybkedznsdvcn",
		},
	} {
		exact := result(t, e.rpc("kt_searchTokens", map[string]any{
			"query": tc.exact, "networks": []string{tc.network},
		}))
		if rows := exact["tokens"].([]any); len(rows) != 1 {
			t.Fatalf("exact Base58 identity %q = %v, want one row", tc.exact, rows)
		}
		got := result(t, e.rpc("kt_searchTokens", map[string]any{
			"query": tc.modified, "networks": []string{tc.network},
		}))
		if rows := got["tokens"].([]any); len(rows) != 0 {
			t.Fatalf("case-modified Base58 identity %q matched official rows: %v", tc.modified, rows)
		}
	}
}

func TestSearchOfficialTokensKeepsEVMContractQueriesCaseInsensitive(t *testing.T) {
	e := newEnv(t, nil)
	got := result(t, e.rpc("kt_searchTokens", map[string]any{
		"query":    "0xDAC17F958D2EE523A2206206994597C13D831EC7",
		"networks": []string{"eth-mainnet"},
	}))
	if rows := got["tokens"].([]any); len(rows) != 1 {
		t.Fatalf("case-modified EVM identity = %v, want one row", rows)
	}
}

package handlers_test

import (
	"testing"

	"ktwallet/gateway/internal/rpc"
)

// Public Gateway methods must use an exact request schema. Go's default JSON
// decoder is intentionally permissive: it ignores unknown fields, matches
// struct fields case-insensitively and accepts duplicate keys. Those behaviors
// are unsafe at a wallet trust boundary because the caller and server can
// disagree about which transaction, identity or privacy decision was made.
func TestParameterizedPublicMethodsRejectNonCanonicalJSON(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		method string
		params string
	}{
		{
			name:   "portfolio case alias",
			method: "kt_getPortfolio",
			params: `{"Accounts":[{"chain":"eth","network":"eth-mainnet","address":"0x1111111111111111111111111111111111111111"}]}`,
		},
		{
			name:   "balances unknown field",
			method: "kt_getBalances",
			params: `{"chain":"eth","network":"eth-mainnet","address":"0x1111111111111111111111111111111111111111","unexpected":true}`,
		},
		{
			name:   "balances nested duplicate field",
			method: "kt_getBalances",
			params: `{"chain":"eth","network":"eth-mainnet","address":"0x1111111111111111111111111111111111111111","tokens":[{"contract":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","contract":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","decimals":18,"symbol":"TKN"}]}`,
		},
		{
			name:   "prices case alias",
			method: "kt_getPrices",
			params: `{"Symbols":["ETH"]}`,
		},
		{
			name:   "chain params unknown field",
			method: "kt_getChainParams",
			params: `{"chain":"eth","network":"eth-mainnet","address":"0x1111111111111111111111111111111111111111","unexpected":true}`,
		},
		{
			name:   "simulation case alias",
			method: "kt_simulateEvmTransfer",
			params: `{"chain":"eth","network":"eth-mainnet","from":"0x1111111111111111111111111111111111111111","to":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","value":"1","Data":"0x"}`,
		},
		{
			name:   "gas estimate unknown field",
			method: "kt_estimateEvmGas",
			params: `{"chain":"eth","network":"eth-mainnet","from":"0x1111111111111111111111111111111111111111","to":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","value":"1","data":"0x","unexpected":true}`,
		},
		{
			name:   "spendable balances unknown field",
			method: "kt_getEvmSpendableBalances",
			params: `{"chain":"eth","network":"eth-mainnet","address":"0x1111111111111111111111111111111111111111","unexpected":true}`,
		},
		{
			name:   "history duplicate field",
			method: "kt_getHistory",
			params: `{"chain":"eth","network":"eth-mainnet","address":"0x1111111111111111111111111111111111111111","limit":1,"limit":2}`,
		},
		{
			name:   "transaction status case alias",
			method: "kt_getTransactionStatus",
			params: `{"chain":"eth","network":"eth-mainnet","Hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`,
		},
		{
			name:   "token search unknown field",
			method: "kt_searchTokens",
			params: `{"query":"USDT","unexpected":true}`,
		},
		{
			name:   "token risk case alias",
			method: "kt_checkTokenRisk",
			params: `{"chain":"bnb","network":"bnb-testnet","Contract":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`,
		},
		{
			name:   "token approvals unknown field",
			method: "kt_getEvmTokenApprovals",
			params: `{"chain":"eth","network":"eth-mainnet","address":"0x1111111111111111111111111111111111111111","privacyConsent":true,"unexpected":true}`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			e := newEnv(t, nil)
			assertErrCode(t, e.rpc(tc.method, tc.params), rpc.CodeInvalidParams)
		})
	}
}

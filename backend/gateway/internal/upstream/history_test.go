package upstream

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestEtherscanNullResultIsUnavailableNotEmptyHistory(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"0","message":"chain not supported","result":null}`))
	}))
	defer server.Close()

	client := NewEtherscan(server.URL, "", server.Client(), time.Second)
	txs, err := client.TxList(context.Background(), 56, "0x1111111111111111111111111111111111111111", 20)
	if err == nil {
		t.Fatalf("null result must fail closed, got empty success: %#v", txs)
	}
}

func TestEtherscanResponseRejectsAmbiguousProviderJSON(t *testing.T) {
	t.Parallel()

	const row = `{"blockNumber":"123","blockHash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"timeStamp":"1700000000","hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",` +
		`"from":"0x1111111111111111111111111111111111111111",` +
		`"to":"0x2222222222222222222222222222222222222222","value":"1",` +
		`"isError":"0","txreceipt_status":"1"}`
	valid := fmt.Sprintf(`{"status":"1","message":"OK","result":[%s]}`, row)
	rowHashAlias := strings.Replace(row, `"hash":`, `"Hash":`, 1)
	rowDuplicateHash := strings.Replace(row, `"hash":`, `"hash":"0xdead","hash":`, 1)
	rowDuplicateValue := strings.Replace(row, `"value":"1"`, `"value":"2","value":"1"`, 1)

	tests := []struct {
		name    string
		payload string
	}{
		{"status case alias", strings.Replace(valid, `"status":`, `"Status":`, 1)},
		{"result case alias", strings.Replace(valid, `"result":`, `"Result":`, 1)},
		{"duplicate status ending success", strings.Replace(valid, `"status":"1"`, `"status":"0","status":"1"`, 1)},
		{"duplicate result ending valid", strings.Replace(valid, `"result":`, `"result":[],"result":`, 1)},
		{"success status with rejection message", strings.Replace(valid, `"message":"OK"`, `"message":"NOTOK"`, 1)},
		{"rate limit disguised as empty result", `{"status":"0","message":"Max rate limit reached","result":[]}`},
		{"no transactions status with nonempty result", fmt.Sprintf(`{"status":"0","message":"No transactions found","result":[%s]}`, row)},
		{"transaction hash case alias", fmt.Sprintf(`{"status":"1","message":"OK","result":[%s]}`, rowHashAlias)},
		{"duplicate transaction hash", fmt.Sprintf(`{"status":"1","message":"OK","result":[%s]}`, rowDuplicateHash)},
		{"duplicate transaction value", fmt.Sprintf(`{"status":"1","message":"OK","result":[%s]}`, rowDuplicateValue)},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tc.payload))
			}))
			defer server.Close()

			txs, err := NewEtherscan(server.URL, "", server.Client(), time.Second).
				TxList(context.Background(), 1, "0x1111111111111111111111111111111111111111", 20)
			if err == nil {
				t.Fatalf("ambiguous explorer response must fail closed, got %#v", txs)
			}
		})
	}
}

func TestExplorerHistoryAllowsAdditiveProviderFields(t *testing.T) {
	t.Parallel()

	rows, rejected, err := decodeExplorerAccountEnvelope([]byte(
		`{"status":"1","message":"OK","providerVersion":"v2","result":[]}`,
	))
	if err != nil || rejected || rows == nil {
		t.Fatalf("additive envelope field broke history: rows=%#v rejected=%v err=%v", rows, rejected, err)
	}
	normal, err := decodeEtherscanTx(json.RawMessage(
		`{"timeStamp":"1700000000",` +
			`"hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",` +
			`"from":"0x1111111111111111111111111111111111111111",` +
			`"to":"0x2222222222222222222222222222222222222222","value":"1",` +
			`"isError":"0","futureField":{"version":2}}`,
	))
	if err != nil || normal.Value != "1" {
		t.Fatalf("additive normal row field broke history: tx=%#v err=%v", normal, err)
	}

	// Captured from the current provider tokentx shape. statusRep was added
	// after the original strict allowlist shipped. It is intentionally ignored:
	// block location remains the reviewed execution evidence for token logs.
	token, err := decodeEtherscanTokenTx(json.RawMessage(`{
		"blockNumber":"75445526","timeStamp":"1786135052",
		"hash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
		"blockHash":"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
		"from":"0x1111111111111111111111111111111111111111",
		"to":"0x2222222222222222222222222222222222222222","value":"1000000",
		"tokenSymbol":"USDT","tokenDecimal":"6",
		"contractAddress":"0x3333333333333333333333333333333333333333",
		"transactionIndex":"2","confirmations":"12","logIndex":"7",
		"statusRep":"1","futureIndexerField":[]
	}`))
	if err != nil || EtherscanTokenExecutionStatus(token) != ExecutionConfirmed {
		t.Fatalf("current token row shape broke history: tx=%#v err=%v", token, err)
	}
}

func TestExplorerHistoryKeepsValidRowsWhenOneRowIsMalformed(t *testing.T) {
	t.Parallel()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		var row string
		switch r.URL.Query().Get("action") {
		case "txlist":
			row = `{"timeStamp":"1700000000",` +
				`"hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",` +
				`"from":"0x1111111111111111111111111111111111111111",` +
				`"to":"0x2222222222222222222222222222222222222222","value":"1","isError":"0"}`
		case "tokentx":
			row = `{"blockNumber":"123","timeStamp":"1700000000",` +
				`"hash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",` +
				`"blockHash":"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",` +
				`"from":"0x1111111111111111111111111111111111111111",` +
				`"to":"0x2222222222222222222222222222222222222222","value":"1",` +
				`"tokenSymbol":"USDC","tokenDecimal":"6",` +
				`"contractAddress":"0x3333333333333333333333333333333333333333",` +
				`"transactionIndex":"0","confirmations":"1","logIndex":"0"}`
		default:
			row = `{"timeStamp":"1700000000",` +
				`"hash":"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",` +
				`"traceId":"0_1","from":"0x1111111111111111111111111111111111111111",` +
				`"to":"0x2222222222222222222222222222222222222222","value":"1","isError":"0"}`
		}
		_, _ = fmt.Fprintf(w, `{"status":"1","message":"OK","result":[{},%s]}`, row)
	}))
	defer server.Close()

	client := NewEtherscan(server.URL, "", server.Client(), time.Second)
	if rows, err := client.TxList(context.Background(), 1, "0x1111111111111111111111111111111111111111", 20); err != nil || len(rows) != 1 {
		t.Fatalf("normal history discarded valid row: rows=%#v err=%v", rows, err)
	}
	if rows, err := client.TokenTxList(context.Background(), 1, "0x1111111111111111111111111111111111111111", 20); err != nil || len(rows) != 1 {
		t.Fatalf("token history discarded valid row: rows=%#v err=%v", rows, err)
	}
	if rows, err := client.InternalTxList(context.Background(), 1, "0x1111111111111111111111111111111111111111", 20); err != nil || len(rows) != 1 {
		t.Fatalf("internal history discarded valid row: rows=%#v err=%v", rows, err)
	}
}

func TestExplorerAccountEnvelopeAllowsOnlyDocumentedEmptyHistory(t *testing.T) {
	t.Parallel()

	for _, payload := range []string{
		`{"status":"1","message":"OK","result":[]}`,
		`{"status":"0","message":"No transactions found","result":[]}`,
		`{"status":"0","message":"No internal transactions found","result":[]}`,
		`{"status":"0","message":"No token transfers found","result":[]}`,
	} {
		rows, rejected, err := decodeExplorerAccountEnvelope([]byte(payload))
		if err != nil || rejected || rows == nil || len(rows) != 0 {
			t.Fatalf("documented empty history was not preserved: rows=%#v rejected=%v err=%v", rows, rejected, err)
		}
	}

	for _, payload := range []string{
		`{"status":"0","message":"NOTOK","result":"Max rate limit reached"}`,
		`{"status":"0","message":"chain not supported","result":null}`,
		`{"status":"0","message":"No transactions found","result":[{}]}`,
	} {
		rows, rejected, err := decodeExplorerAccountEnvelope([]byte(payload))
		if err != nil || !rejected || rows != nil {
			t.Fatalf("provider rejection was confused with empty history: rows=%#v rejected=%v err=%v", rows, rejected, err)
		}
	}
}

func TestExplorerRowsAllowReviewedEtherscanAndBlockscoutShapes(t *testing.T) {
	t.Parallel()

	normal := json.RawMessage(`{
		"blockNumber":"21933251","blockHash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"timeStamp":"1740662711","hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		"nonce":"328","transactionIndex":"128","from":"0x1111111111111111111111111111111111111111",
		"to":"0x2222222222222222222222222222222222222222","value":"1000000000000000",
		"gas":"21000","gasPrice":"1000000000","input":"0x","methodId":"0x","functionName":"",
		"contractAddress":"","cumulativeGasUsed":"15000000","txreceipt_status":"1","gasUsed":"21000",
		"confirmations":"42","isError":"0","maxFeePerGas":"2000000000","maxPriorityFeePerGas":"1",
		"type":"2","l1Fee":"0","l1GasPrice":"0","l1GasUsed":"0","l1FeeScalar":"0",
		"blobGasUsed":"0","blobGasPrice":"0","authorizationList":[]
	}`)
	tx, err := decodeEtherscanTx(normal)
	if err != nil || tx.Hash == "" || EtherscanExecutionStatus(tx.IsError, tx.ReceiptStatus) != ExecutionConfirmed {
		t.Fatalf("reviewed normal transaction shape rejected: tx=%#v err=%v", tx, err)
	}

	token := json.RawMessage(`{
		"blockNumber":"21933251","timeStamp":"1740662711",
		"hash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","nonce":"12",
		"blockHash":"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
		"from":"0x1111111111111111111111111111111111111111",
		"contractAddress":"0x3333333333333333333333333333333333333333",
		"to":"0x2222222222222222222222222222222222222222","value":"2500000",
		"tokenName":"USD Coin","tokenSymbol":"USDC","tokenDecimal":"6","transactionIndex":"81",
		"gas":"90000","gasPrice":"1000000000","gasUsed":"52211","cumulativeGasUsed":"15000000",
		"input":"deprecated","methodId":"0xa9059cbb","functionName":"transfer(address,uint256)",
		"confirmations":"8","logIndex":"7","maxFeePerGas":"2","maxPriorityFeePerGas":"1","type":"2"
	}`)
	tokenTx, err := decodeEtherscanTokenTx(token)
	if err != nil || tokenTx.LogIndex != "7" || EtherscanTokenExecutionStatus(tokenTx) != ExecutionConfirmed {
		t.Fatalf("reviewed token transaction shape rejected: tx=%#v err=%v", tokenTx, err)
	}

	etherscanInternal := json.RawMessage(`{
		"blockNumber":"21933251","timeStamp":"1740662711",
		"hash":"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
		"from":"0x1111111111111111111111111111111111111111",
		"to":"0x2222222222222222222222222222222222222222","value":"42","contractAddress":"",
		"input":"0x","type":"call","gas":"2300","gasUsed":"0","traceId":"0_1","isError":"0","errCode":""
	}`)
	internalTx, err := decodeEtherscanInternalTx(etherscanInternal)
	if err != nil || internalTx.CanonicalTraceID() != "0_1" || internalTx.CanonicalHash() == "" {
		t.Fatalf("reviewed Etherscan internal shape rejected: tx=%#v err=%v", internalTx, err)
	}

	blockscoutInternal := json.RawMessage(`{
		"blockNumber":"21933251","timeStamp":"1740662711",
		"transactionHash":"0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		"from":"0x1111111111111111111111111111111111111111",
		"to":"0x2222222222222222222222222222222222222222","value":"42","contractAddress":"",
		"input":"0x","type":"call","callType":"call","gas":"2300","gasUsed":"0","index":"0_1",
		"isError":"0","txreceipt_status":"1","errCode":""
	}`)
	internalTx, err = decodeEtherscanInternalTx(blockscoutInternal)
	if err != nil || internalTx.CanonicalTraceID() != "0_1" || internalTx.CanonicalHash() == "" {
		t.Fatalf("reviewed Blockscout internal shape rejected: tx=%#v err=%v", internalTx, err)
	}
}

func TestExplorerRowsRejectInvalidCriticalValues(t *testing.T) {
	t.Parallel()

	const normal = `{"timeStamp":"1700000000",` +
		`"hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",` +
		`"from":"0x1111111111111111111111111111111111111111",` +
		`"to":"0x2222222222222222222222222222222222222222","value":"1","isError":"0"}`
	const token = `{"blockNumber":"123","timeStamp":"1700000000",` +
		`"hash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",` +
		`"blockHash":"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",` +
		`"from":"0x1111111111111111111111111111111111111111",` +
		`"to":"0x2222222222222222222222222222222222222222","value":"1",` +
		`"tokenSymbol":"USDC","tokenDecimal":"6",` +
		`"contractAddress":"0x3333333333333333333333333333333333333333",` +
		`"transactionIndex":"0","confirmations":"1","logIndex":"0"}`
	const internal = `{"timeStamp":"1700000000",` +
		`"hash":"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",` +
		`"traceId":"0_1","from":"0x1111111111111111111111111111111111111111",` +
		`"to":"0x2222222222222222222222222222222222222222","value":"1","isError":"0"}`

	tests := []struct {
		name   string
		row    string
		decode func(json.RawMessage) error
	}{
		{"normal short hash", strings.Replace(normal, strings.Repeat("b", 64), "bb", 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTx(raw); return err }},
		{"normal invalid sender", strings.Replace(normal, "0x1111111111111111111111111111111111111111", "0x1", 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTx(raw); return err }},
		{"normal negative value", strings.Replace(normal, `"value":"1"`, `"value":"-1"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTx(raw); return err }},
		{"normal uint256 overflow", strings.Replace(normal, `"value":"1"`, `"value":"`+strings.Repeat("9", 78)+`"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTx(raw); return err }},
		{"normal timestamp overflow", strings.Replace(normal, `"timeStamp":"1700000000"`, `"timeStamp":"9223372036854776"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTx(raw); return err }},
		{"normal invalid status", strings.Replace(normal, `"isError":"0"`, `"isError":"false"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTx(raw); return err }},
		{"token zero block", strings.Replace(token, `"blockNumber":"123"`, `"blockNumber":"0"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTokenTx(raw); return err }},
		{"token invalid block hash", strings.Replace(token, strings.Repeat("d", 64), "dd", 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTokenTx(raw); return err }},
		{"token decimal overflow", strings.Replace(token, `"tokenDecimal":"6"`, `"tokenDecimal":"256"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTokenTx(raw); return err }},
		{"token invalid transaction index", strings.Replace(token, `"transactionIndex":"0"`, `"transactionIndex":"-1"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTokenTx(raw); return err }},
		{"token invalid log index", strings.Replace(token, `"logIndex":"0"`, `"logIndex":"0x1"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTokenTx(raw); return err }},
		{"token control character symbol", strings.Replace(token, `"tokenSymbol":"USDC"`, `"tokenSymbol":"USDC\n"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanTokenTx(raw); return err }},
		{"internal both hash families", strings.Replace(internal, `"hash":`, `"transactionHash":"0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","hash":`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanInternalTx(raw); return err }},
		{"internal both trace families", strings.Replace(internal, `"traceId":`, `"index":"0","traceId":`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanInternalTx(raw); return err }},
		{"internal malformed trace", strings.Replace(internal, `"traceId":"0_1"`, `"traceId":"0__1"`, 1), func(raw json.RawMessage) error { _, err := decodeEtherscanInternalTx(raw); return err }},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if err := tc.decode(json.RawMessage(tc.row)); err == nil {
				t.Fatal("invalid critical explorer value was accepted")
			}
		})
	}
}

func TestEtherscanProviderErrorsAreRedactedAndPaginationIsBounded(t *testing.T) {
	t.Parallel()

	t.Run("provider rejection", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(`{"status":"0","message":"NOTOK","result":"secret provider detail"}`))
		}))
		defer server.Close()

		_, err := NewEtherscan(server.URL, "key", server.Client(), time.Second).
			TxList(context.Background(), 1, "0x1111111111111111111111111111111111111111", 20)
		var unavailable *Unavailable
		if !errors.As(err, &unavailable) || err.Error() != "upstream temporarily unavailable" ||
			unavailable.Message != "explorer rejected request" || strings.Contains(err.Error(), "secret") {
			t.Fatalf("provider detail crossed the trust boundary: %#v / %v", unavailable, err)
		}
	})

	t.Run("newest bounded page", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			query := r.URL.Query()
			for key, want := range map[string]string{
				"chainid": "137", "module": "account", "action": "txlist",
				"address": "0x1111111111111111111111111111111111111111",
				"page":    "1", "offset": "17", "sort": "desc", "apikey": "key",
			} {
				if query.Get(key) != want {
					t.Errorf("query %s = %q, want %q", key, query.Get(key), want)
				}
			}
			_, _ = w.Write([]byte(`{"status":"1","message":"OK","result":[]}`))
		}))
		defer server.Close()

		rows, err := NewEtherscan(server.URL, "key", server.Client(), time.Second).
			TxList(context.Background(), 137, "0x1111111111111111111111111111111111111111", 17)
		if err != nil || rows == nil || len(rows) != 0 {
			t.Fatalf("bounded empty page failed: rows=%#v err=%v", rows, err)
		}
	})
}

func TestHeliusResponseRejectsAmbiguousProviderJSON(t *testing.T) {
	t.Parallel()

	const row = `{"signature":"sig","slot":123,"blockTime":1700000200,"type":"transfer",` +
		`"fromUserAccount":"from","toUserAccount":"to",` +
		`"mint":"So11111111111111111111111111111111111111111",` +
		`"amount":"42","decimals":9,"uiAmount":"0.000000042","confirmationStatus":"finalized",` +
		`"transactionIdx":1,"instructionIdx":2,"innerInstructionIdx":null}`
	validResult := fmt.Sprintf(`{"data":[%s]}`, row)
	rowAmountAlias := strings.Replace(row, `"amount":"42"`, `"Amount":"42"`, 1)
	rowDuplicateAmount := strings.Replace(row, `"amount":"42"`, `"amount":"1","amount":"42"`, 1)

	tests := []struct {
		name    string
		payload string
	}{
		{"wrong response id", fmt.Sprintf(`{"jsonrpc":"2.0","id":"other","result":%s}`, validResult)},
		{"missing response id", fmt.Sprintf(`{"jsonrpc":"2.0","result":%s}`, validResult)},
		{"wrong version", fmt.Sprintf(`{"jsonrpc":"1.0","id":"kt-wallet","result":%s}`, validResult)},
		{"result case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","Result":%s}`, validResult)},
		{"result case collision", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[]},"Result":%s}`, validResult)},
		{"duplicate response id ending expected", fmt.Sprintf(`{"jsonrpc":"2.0","id":"other","id":"kt-wallet","result":%s}`, validResult)},
		{"duplicate result ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[]},"result":%s}`, validResult)},
		{"data case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"Data":[%s]}}`, row)},
		{"duplicate data ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[],"data":[%s]}}`, row)},
		{"transfer field alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[%s]}}`, rowAmountAlias)},
		{"duplicate transfer amount", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[%s]}}`, rowDuplicateAmount)},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tc.payload))
			}))
			defer server.Close()

			transfers, err := NewHelius(server.URL, "key", server.Client(), time.Second).
				Transfers(context.Background(), "wallet", 20)
			if err == nil {
				t.Fatalf("ambiguous Helius response must fail closed, got %#v", transfers)
			}
		})
	}
}

func TestHeliusHistoryAllowsAdditiveProviderFields(t *testing.T) {
	t.Parallel()
	payload := `{"jsonrpc":"2.0","id":"kt-wallet","providerVersion":2,"result":{` +
		`"futurePageInfo":{},"paginationToken":null,"data":[{"signature":"sig","blockTime":1700000200,` +
		`"type":"transfer","fromUserAccount":"from","toUserAccount":"to",` +
		`"mint":"So11111111111111111111111111111111111111111","amount":"42",` +
		`"decimals":9,"uiAmount":"NaN","feeAmount":{},"confirmationStatus":"finalized",` +
		`"transactionIdx":1,"instructionIdx":2,"futureField":[]},{}]}}`
	transfers, rejected, err := decodeHeliusTransfers([]byte(payload))
	if err != nil || rejected || len(transfers) != 1 || transfers[0].Amount != "42" {
		t.Fatalf("additive Helius fields broke history: transfers=%#v rejected=%v err=%v", transfers, rejected, err)
	}
}

func TestHeliusResponseRejectsInvalidCriticalTransferValues(t *testing.T) {
	t.Parallel()

	const row = `{"signature":"sig","slot":123,"blockTime":1700000200,"type":"transfer",` +
		`"fromUserAccount":"from","toUserAccount":"to",` +
		`"mint":"So11111111111111111111111111111111111111111",` +
		`"amount":"42","decimals":9,"uiAmount":"0.000000042","confirmationStatus":"finalized",` +
		`"transactionIdx":1,"instructionIdx":2,"innerInstructionIdx":null}`
	tests := []struct {
		name string
		row  string
	}{
		{"negative raw amount", strings.Replace(row, `"amount":"42"`, `"amount":"-42"`, 1)},
		{"fractional raw amount", strings.Replace(row, `"amount":"42"`, `"amount":"4.2"`, 1)},
		{"unknown transfer type", strings.Replace(row, `"type":"transfer"`, `"type":"airdrop"`, 1)},
		{"both owners null", strings.Replace(row, `"fromUserAccount":"from","toUserAccount":"to"`, `"fromUserAccount":null,"toUserAccount":null`, 1)},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := fmt.Sprintf(`{"data":[%s]}`, tc.row)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = fmt.Fprintf(w, `{"jsonrpc":"2.0","id":"kt-wallet","result":%s}`, result)
			}))
			defer server.Close()

			transfers, err := NewHelius(server.URL, "key", server.Client(), time.Second).
				Transfers(context.Background(), "wallet", 20)
			if err == nil {
				t.Fatalf("invalid Helius value must fail closed, got %#v", transfers)
			}
		})
	}
}

func TestHeliusResponseAllowsStandardErrorDataAndEmptyHistory(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		payload   string
		wantError bool
	}{
		{
			name:      "standard error data",
			payload:   `{"jsonrpc":"2.0","id":"kt-wallet","error":{"code":-32000,"message":"limited","data":{"retryAfter":1}}}`,
			wantError: true,
		},
		{
			name:    "empty transfer array",
			payload: `{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[]}}`,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tc.payload))
			}))
			defer server.Close()

			transfers, err := NewHelius(server.URL, "key", server.Client(), time.Second).
				Transfers(context.Background(), "wallet", 20)
			if tc.wantError {
				var unavailable *Unavailable
				if !errors.As(err, &unavailable) || unavailable.Message != "history provider rejected request" {
					t.Fatalf("standard error object was not preserved: %v", err)
				}
				return
			}
			if err != nil || transfers == nil || len(transfers) != 0 {
				t.Fatalf("empty history must remain a valid non-nil result: transfers=%#v err=%v", transfers, err)
			}
		})
	}
}

func TestHeliusResponseAllowsCurrentOfficialTransferFields(t *testing.T) {
	t.Parallel()

	payload := `{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[` +
		`{"signature":"fee-transfer","slot":409259683,"blockTime":1774635210,"type":"transfer",` +
		`"fromUserAccount":"from","toUserAccount":"to","fromTokenAccount":"from-token",` +
		`"toTokenAccount":"to-token","mint":"mint","amount":"48650000","decimals":5,` +
		`"uiAmount":"486.5","feeAmount":"13450000","feeUiAmount":"134.5",` +
		`"confirmationStatus":"finalized","transactionIdx":1315,"instructionIdx":4,"innerInstructionIdx":0},` +
		`{"signature":"mint-transfer","slot":409259684,"blockTime":1774635211,"type":"mint",` +
		`"fromUserAccount":null,"toUserAccount":"wallet",` +
		`"toTokenAccount":"to-token","mint":"mint","amount":"1","decimals":0,"uiAmount":"1",` +
		`"confirmationStatus":"finalized","transactionIdx":1316,"instructionIdx":1,"innerInstructionIdx":null}` +
		`],"paginationToken":"409259684:1316:1:0:mint"}}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(payload))
	}))
	defer server.Close()

	transfers, err := NewHelius(server.URL, "key", server.Client(), time.Second).
		Transfers(context.Background(), "wallet", 20)
	if err != nil || len(transfers) != 2 {
		t.Fatalf("current official response shape must remain compatible: transfers=%#v err=%v", transfers, err)
	}
	if transfers[0].Amount != "48650000" || transfers[0].InnerInstructionIdx == nil ||
		transfers[1].FromUserAccount != "" || transfers[1].ToUserAccount != "wallet" {
		t.Fatalf("official transfer semantics were not preserved: %#v", transfers)
	}
}

func TestAlchemyTransferResponseRejectsAmbiguousProviderJSON(t *testing.T) {
	t.Parallel()

	const row = `{"blockNum":"0xabc","uniqueId":"0xevent:external",` +
		`"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"from":"0x1111111111111111111111111111111111111111",` +
		`"to":"0x2222222222222222222222222222222222222222",` +
		`"value":1,"erc721TokenId":null,"erc1155Metadata":null,"tokenId":null,` +
		`"asset":"ETH","category":"external",` +
		`"rawContract":{"value":"0x1","address":null,"decimal":"0x12"},` +
		`"metadata":{"blockTimestamp":"2026-07-29T01:01:00Z"}}`
	validResult := fmt.Sprintf(`{"transfers":[%s],"pageKey":""}`, row)
	rowHashAlias := strings.Replace(row, `"hash":`, `"Hash":`, 1)
	rowDuplicateHash := strings.Replace(row, `"hash":`, `"hash":"0xdead","hash":`, 1)
	rowRawAlias := strings.Replace(row, `"value":"0x1"`, `"Value":"0x1"`, 1)
	rowRawDuplicate := strings.Replace(row, `"value":"0x1"`, `"value":"0x2","value":"0x1"`, 1)
	rowTimestampAlias := strings.Replace(row, `"blockTimestamp":`, `"BlockTimestamp":`, 1)
	rowTimestampDuplicate := strings.Replace(row, `"blockTimestamp":`, `"blockTimestamp":"2020-01-01T00:00:00Z","blockTimestamp":`, 1)

	tests := []struct {
		name    string
		payload string
	}{
		{"wrong response id", fmt.Sprintf(`{"jsonrpc":"2.0","id":2,"result":%s}`, validResult)},
		{"missing response id", fmt.Sprintf(`{"jsonrpc":"2.0","result":%s}`, validResult)},
		{"wrong version", fmt.Sprintf(`{"jsonrpc":"1.0","id":1,"result":%s}`, validResult)},
		{"result case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"Result":%s}`, validResult)},
		{"result case collision", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[]},"Result":%s}`, validResult)},
		{"duplicate response id ending expected", fmt.Sprintf(`{"jsonrpc":"2.0","id":2,"id":1,"result":%s}`, validResult)},
		{"duplicate result ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[]},"result":%s}`, validResult)},
		{"transfers case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"Transfers":[%s]}}`, row)},
		{"duplicate transfers ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[],"transfers":[%s]}}`, row)},
		{"transfer hash case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowHashAlias)},
		{"duplicate transfer hash", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowDuplicateHash)},
		{"raw value case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowRawAlias)},
		{"duplicate raw value", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowRawDuplicate)},
		{"timestamp case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowTimestampAlias)},
		{"duplicate timestamp", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowTimestampDuplicate)},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tc.payload))
			}))
			defer server.Close()

			client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
			transfers, err := client.requestEndpoint(context.Background(), server.URL, []byte(`{}`))
			if err == nil {
				t.Fatalf("ambiguous Alchemy response must fail closed, got %#v", transfers)
			}
		})
	}
}

func TestAlchemyTransferResponseRejectsInvalidFinancialFields(t *testing.T) {
	t.Parallel()

	const row = `{"blockNum":"0xabc","uniqueId":"0xevent:external",` +
		`"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"from":"0x1111111111111111111111111111111111111111",` +
		`"to":"0x2222222222222222222222222222222222222222",` +
		`"asset":"ETH","category":"external",` +
		`"rawContract":{"value":"0x1","address":null,"decimal":"0x12"},` +
		`"metadata":{"blockTimestamp":"2026-07-29T01:01:00Z"}}`
	tests := []struct {
		name string
		row  string
	}{
		{"missing block number", strings.Replace(row, `"blockNum":"0xabc",`, "", 1)},
		{"invalid block number", strings.Replace(row, `"blockNum":"0xabc"`, `"blockNum":"latest"`, 1)},
		{"invalid transaction hash", strings.Replace(row, `"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"`, `"hash":"0x1234"`, 1)},
		{"invalid sender", strings.Replace(row, `"from":"0x1111111111111111111111111111111111111111"`, `"from":"0x1234"`, 1)},
		{"invalid recipient", strings.Replace(row, `"to":"0x2222222222222222222222222222222222222222"`, `"to":"0x1234"`, 1)},
		{"unsupported category", strings.Replace(row, `"category":"external"`, `"category":"erc721"`, 1)},
		{"missing raw decimal", strings.Replace(row, `,"decimal":"0x12"`, "", 1)},
		{"invalid raw value", strings.Replace(row, `"value":"0x1"`, `"value":"-1"`, 1)},
		{"zero raw value excluded by request", strings.Replace(row, `"value":"0x1"`, `"value":"0x0"`, 1)},
		{"decimal exceeds ERC20 range", strings.Replace(row, `"decimal":"0x12"`, `"decimal":"0x100"`, 1)},
		{"native row with token contract", strings.Replace(row, `"address":null`, `"address":"0x3333333333333333333333333333333333333333"`, 1)},
		{"token row without contract", strings.Replace(row, `"category":"external"`, `"category":"erc20"`, 1)},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := fmt.Sprintf(`{"transfers":[%s]}`, tc.row)
			payload := fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":%s}`, result)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(payload))
			}))
			defer server.Close()

			client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
			transfers, err := client.requestEndpoint(context.Background(), server.URL, []byte(`{}`))
			if err == nil {
				t.Fatalf("invalid Alchemy financial field must fail closed, got %#v", transfers)
			}
		})
	}
}

func TestAlchemyTransferResponseAllowsDocumentedNullableFields(t *testing.T) {
	t.Parallel()

	payload := `{"jsonrpc":"2.0","id":1,"providerVersion":"2026-08","result":{"transfers":[` +
		`{"blockNum":"0xabc","uniqueId":"0xcreate:external",` +
		`"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"from":"0x1111111111111111111111111111111111111111","to":null,` +
		`"value":1,"erc721TokenId":null,"erc1155Metadata":null,"tokenId":null,` +
		`"asset":"ETH","category":"external","typeTraceAddress":null,"futureField":{},` +
		`"rawContract":{"value":"0x1","address":null,"decimal":"0x12","futureRaw":true},"metadata":null},` +
		`{"blockNum":"0xabd","uniqueId":"0xtoken:log:1",` +
		`"hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",` +
		`"from":"0x2222222222222222222222222222222222222222",` +
		`"to":"0x1111111111111111111111111111111111111111",` +
		`"asset":"USDC","category":"erc20","erc1155Metadata":[],` +
		`"rawContract":{"value":"0x2","address":"0x3333333333333333333333333333333333333333","decimal":"0x6"},` +
		`"metadata":{"blockTimestamp":"2026-07-29T01:01:00.123Z","futureMetadata":[]}},` +
		`{}],"pageKey":null,"futurePageInfo":{}}}`
	transfers, rejected, err := decodeAlchemyTransfers([]byte(payload))
	if err != nil || rejected || len(transfers) != 2 {
		t.Fatalf("documented Alchemy shape must decode: transfers=%#v rejected=%v err=%v", transfers, rejected, err)
	}
	if transfers[0].To != "" || transfers[0].BlockTime != "" ||
		transfers[1].Raw.Address != "0x3333333333333333333333333333333333333333" ||
		transfers[1].BlockTime != "2026-07-29T01:01:00.123Z" {
		t.Fatalf("documented nullable/metadata semantics were not preserved: %#v", transfers)
	}
}

func TestAlchemyTransfersPreservesValidDirectionWithoutCachingPartialEmpty(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name        string
		incoming    string
		wantCount   int
		wantFailure bool
	}{
		{
			name: "valid incoming survives outgoing failure",
			incoming: `[{"blockNum":"0xabc","uniqueId":"0xtoken:log:1",` +
				`"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
				`"from":"0x2222222222222222222222222222222222222222",` +
				`"to":"0x1111111111111111111111111111111111111111",` +
				`"asset":"USDT","category":"erc20","erc1155Metadata":[],` +
				`"rawContract":{"value":"0xf4240","address":"0x3333333333333333333333333333333333333333",` +
				`"decimal":"0x6"},"metadata":{"blockTimestamp":"2026-08-08T01:02:03Z"}}]`,
			wantCount: 1,
		},
		{
			name:        "successful empty incoming does not hide outgoing failure",
			incoming:    `[]`,
			wantFailure: true,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				var request struct {
					Params []map[string]any `json:"params"`
				}
				if err := json.NewDecoder(r.Body).Decode(&request); err != nil || len(request.Params) != 1 {
					http.Error(w, "bad request", http.StatusBadRequest)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				if request.Params[0]["fromAddress"] != nil {
					_, _ = fmt.Fprint(w, `{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"outgoing unavailable"}}`)
					return
				}
				_, _ = fmt.Fprintf(w, `{"jsonrpc":"2.0","id":1,"result":{"transfers":%s}}`, tc.incoming)
			}))
			defer server.Close()

			transfers, err := NewAlchemy([]string{server.URL}, server.Client(), time.Second).
				Transfers(context.Background(), "0x1111111111111111111111111111111111111111", 20)
			if tc.wantFailure {
				if err == nil {
					t.Fatalf("partial empty page must remain unavailable: %#v", transfers)
				}
				return
			}
			if err != nil || len(transfers) != tc.wantCount {
				t.Fatalf("valid direction was discarded: transfers=%#v err=%v", transfers, err)
			}
		})
	}
}

func TestAlchemyBlockBatchRejectsAmbiguousProviderJSON(t *testing.T) {
	t.Parallel()

	const block = `{"number":"0xabc",` +
		`"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"timestamp":"0x6889777b"}`
	tests := []struct {
		name    string
		payload string
	}{
		{"wrong version", fmt.Sprintf(`[{"jsonrpc":"1.0","id":1,"result":%s}]`, block)},
		{"result case alias", fmt.Sprintf(`[{"jsonrpc":"2.0","id":1,"Result":%s}]`, block)},
		{"duplicate id ending expected", fmt.Sprintf(`[{"jsonrpc":"2.0","id":2,"id":1,"result":%s}]`, block)},
		{"duplicate result ending valid", fmt.Sprintf(`[{"jsonrpc":"2.0","id":1,"result":null,"result":%s}]`, block)},
		{"timestamp case alias", fmt.Sprintf(`[{"jsonrpc":"2.0","id":1,"result":{"Timestamp":"0x6889777b"}}]`)},
		{"duplicate timestamp", fmt.Sprintf(`[{"jsonrpc":"2.0","id":1,"result":{"timestamp":"0x1","timestamp":"0x6889777b"}}]`)},
		{"duplicate batch id", fmt.Sprintf(`[{"jsonrpc":"2.0","id":1,"result":%s},{"jsonrpc":"2.0","id":1,"result":%s}]`, block, block)},
		{"result and error collision", fmt.Sprintf(`[{"jsonrpc":"2.0","id":1,"result":%s,"error":{"code":-1,"message":"failed"}}]`, block)},
		{"unknown error member", `[{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"failed","unexpected":true}}]`},
		{"duplicate error code", `[{"jsonrpc":"2.0","id":1,"error":{"code":-2,"code":-1,"message":"failed"}}]`},
		{"missing error message", `[{"jsonrpc":"2.0","id":1,"error":{"code":-1}}]`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tc.payload))
			}))
			defer server.Close()

			client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
			timestamps, err := client.requestBlockTimestamps(
				context.Background(), server.URL, []byte(`[]`), []string{"0xabc"},
			)
			if err == nil {
				t.Fatalf("ambiguous Alchemy block batch must fail closed, got %#v", timestamps)
			}
		})
	}
}

func TestAlchemyBlockBatchAllowsDocumentedExtensibleBlocks(t *testing.T) {
	t.Parallel()

	const firstTimestamp = "0x6889777b"
	const secondTimestamp = "0x68897780"
	payload := `[` +
		`{"jsonrpc":"2.0","id":2,"providerVersion":"2026-08","result":{"number":"0xabd",` +
		`"hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",` +
		`"parentHash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"transactions":[],"timestamp":"` + secondTimestamp + `"}},` +
		`{"jsonrpc":"2.0","id":1,"result":{"number":"0xabc",` +
		`"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"transactions":[],"timestamp":"` + firstTimestamp + `"}}]`
	blocks := []string{"0xabc", "0xabd"}
	timestamps, rejected, err := decodeAlchemyBlockTimestamps([]byte(payload), blocks)
	if err != nil || rejected {
		t.Fatalf("documented Ethereum blocks must decode: rejected=%v err=%v", rejected, err)
	}
	for i, raw := range []string{firstTimestamp, secondTimestamp} {
		seconds, ok := new(big.Int).SetString(raw[2:], 16)
		if !ok {
			t.Fatal("invalid test timestamp")
		}
		want := time.Unix(seconds.Int64(), 0).UTC().Format(time.RFC3339Nano)
		if got := timestamps[blocks[i]]; got != want {
			t.Fatalf("timestamp[%s]=%q, want %q", blocks[i], got, want)
		}
	}
}

func TestAlchemyBlockBatchReturnsSafeRejection(t *testing.T) {
	t.Parallel()

	payload := `[{"jsonrpc":"2.0","id":1,"error":{` +
		`"code":-32000,"message":"provider detail","data":{"request":"secret"}}}]`
	timestamps, rejected, err := decodeAlchemyBlockTimestamps(
		[]byte(payload), []string{"0xabc"},
	)
	if err != nil || !rejected || timestamps != nil {
		t.Fatalf("standard provider error must be a safe rejection: timestamps=%#v rejected=%v err=%v", timestamps, rejected, err)
	}
}

func TestAlchemyProviderErrorsAreRedacted(t *testing.T) {
	t.Parallel()

	const providerError = `{"jsonrpc":"2.0","id":1,"error":{` +
		`"code":-32000,"message":"provider detail","data":{"request":"secret"}}}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(providerError))
	}))
	defer server.Close()

	client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
	_, historyErr := client.requestEndpoint(
		context.Background(), server.URL, []byte(`{}`),
	)
	var historyUnavailable *Unavailable
	if historyErr == nil || historyErr.Error() != "upstream temporarily unavailable" ||
		!errors.As(historyErr, &historyUnavailable) ||
		historyUnavailable.Upstream != "alchemy" ||
		historyUnavailable.Message != "Alchemy rejected history request" {
		t.Fatalf("history rejection must be fixed and redacted, got %v", historyErr)
	}

	batchServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte("[" + providerError + "]"))
	}))
	defer batchServer.Close()
	_, blockErr := client.requestBlockTimestamps(
		context.Background(), batchServer.URL, []byte(`[]`), []string{"0xabc"},
	)
	var blockUnavailable *Unavailable
	if blockErr == nil || blockErr.Error() != "upstream temporarily unavailable" ||
		!errors.As(blockErr, &blockUnavailable) ||
		blockUnavailable.Upstream != "alchemy" ||
		blockUnavailable.Message != "Alchemy rejected block request" {
		t.Fatalf("block rejection must be fixed and redacted, got %v", blockErr)
	}
}

func TestAlchemyTransfersQueriesBothDirectionsAndUsesRawValues(t *testing.T) {
	var (
		mu         sync.Mutex
		directions = map[string]bool{}
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var request struct {
			Method string           `json:"method"`
			Params []map[string]any `json:"params"`
		}
		if err := json.Unmarshal(body, &request); err != nil {
			t.Fatal(err)
		}
		if request.Method != "alchemy_getAssetTransfers" || len(request.Params) != 1 {
			t.Fatalf("unexpected request: %s", body)
		}
		direction := ""
		for _, key := range []string{"fromAddress", "toAddress"} {
			if request.Params[0][key] != nil {
				direction = key
			}
		}
		mu.Lock()
		directions[direction] = true
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if direction == "toAddress" {
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
				"uniqueId":"0xtoken:log:2","blockNum":"0x101","hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
				"from":"0x2222222222222222222222222222222222222222",
				"to":"0x1111111111111111111111111111111111111111",
				"asset":"USDC","category":"erc20",
				"rawContract":{"value":"0x2625a0","address":"0x3333333333333333333333333333333333333333","decimal":"0x6"},
				"metadata":{"blockTimestamp":"2026-07-29T01:02:03.456Z"}
			}]}}`))
			return
		}
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
		"uniqueId":"0xnative:external","blockNum":"0x100","hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			"from":"0x1111111111111111111111111111111111111111",
			"to":"0x2222222222222222222222222222222222222222",
			"asset":"BNB","category":"external",
			"rawContract":{"value":"0x4d2","address":null,"decimal":"0x12"},
			"metadata":{"blockTimestamp":"2026-07-29T01:01:00Z"}
		}]}}`))
	}))
	defer server.Close()

	client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
	transfers, err := client.Transfers(
		context.Background(),
		"0x1111111111111111111111111111111111111111",
		20,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(transfers) != 2 {
		t.Fatalf("transfers = %#v", transfers)
	}
	mu.Lock()
	defer mu.Unlock()
	if !directions["fromAddress"] || !directions["toAddress"] || directions[""] {
		t.Fatalf("directions = %#v", directions)
	}
	for _, transfer := range transfers {
		if strings.HasPrefix(transfer.UniqueID, "0xtoken") &&
			(transfer.Raw.Value != "0x2625a0" || transfer.BlockTime == "") {
			t.Fatalf("raw token transfer was not preserved: %#v", transfer)
		}
	}
}

func TestAlchemyRetriesWithoutInternalCategory(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		body, _ := io.ReadAll(r.Body)
		if strings.Contains(string(body), `"internal"`) {
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"internal category unsupported"}}`))
			return
		}
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[]}}`))
	}))
	defer server.Close()

	client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
	if _, err := client.Transfers(
		context.Background(),
		"0x1111111111111111111111111111111111111111",
		20,
	); err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 4 {
		t.Fatalf("calls = %d, want two directions plus two category fallbacks", calls.Load())
	}
}

func TestAlchemyBackfillsMissingMetadataFromBlockBatch(t *testing.T) {
	var batchCalls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		if strings.HasPrefix(strings.TrimSpace(string(body)), "[") {
			batchCalls.Add(1)
			_, _ = w.Write([]byte(`[{
				"jsonrpc":"2.0","id":1,
				"result":{"timestamp":"0x6889777b"}
			}]`))
			return
		}
		if strings.Contains(string(body), `"toAddress"`) {
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
				"uniqueId":"0xmissing:external","blockNum":"0xabc","hash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
				"from":"0x2222222222222222222222222222222222222222",
				"to":"0x1111111111111111111111111111111111111111",
				"asset":"BNB","category":"external",
				"rawContract":{"value":"0x1","address":null,"decimal":"0x12"},
				"metadata":null
			}]}}`))
			return
		}
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[]}}`))
	}))
	defer server.Close()

	client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
	transfers, err := client.Transfers(
		context.Background(),
		"0x1111111111111111111111111111111111111111",
		20,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(transfers) != 1 || transfers[0].BlockTime != "2025-07-30T01:38:03Z" {
		t.Fatalf("block time was not backfilled: %#v", transfers)
	}
	if batchCalls.Load() != 1 {
		t.Fatalf("block timestamps should use one batch request, calls = %d", batchCalls.Load())
	}
}

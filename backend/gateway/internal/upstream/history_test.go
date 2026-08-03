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

func TestHeliusResponseRejectsAmbiguousProviderJSON(t *testing.T) {
	t.Parallel()

	const row = `{"signature":"sig","slot":123,"blockTime":1700000200,"type":"transfer",` +
		`"fromUserAccount":"from","toUserAccount":"to",` +
		`"mint":"So11111111111111111111111111111111111111111",` +
		`"amount":"42","decimals":9,"uiAmount":"0.000000042","confirmationStatus":"finalized",` +
		`"transactionIdx":1,"instructionIdx":2,"innerInstructionIdx":null}`
	validResult := fmt.Sprintf(`{"data":[%s]}`, row)
	rowUnknown := strings.Replace(row, `"instructionIdx":2`, `"instructionIdx":2,"unexpected":true`, 1)
	rowAmountAlias := strings.Replace(row, `"amount":"42"`, `"Amount":"42"`, 1)
	rowDuplicateAmount := strings.Replace(row, `"amount":"42"`, `"amount":"1","amount":"42"`, 1)

	tests := []struct {
		name    string
		payload string
	}{
		{"wrong response id", fmt.Sprintf(`{"jsonrpc":"2.0","id":"other","result":%s}`, validResult)},
		{"missing response id", fmt.Sprintf(`{"jsonrpc":"2.0","result":%s}`, validResult)},
		{"wrong version", fmt.Sprintf(`{"jsonrpc":"1.0","id":"kt-wallet","result":%s}`, validResult)},
		{"unknown envelope member", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":%s,"unexpected":true}`, validResult)},
		{"result case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","Result":%s}`, validResult)},
		{"result case collision", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[]},"Result":%s}`, validResult)},
		{"duplicate response id ending expected", fmt.Sprintf(`{"jsonrpc":"2.0","id":"other","id":"kt-wallet","result":%s}`, validResult)},
		{"duplicate result ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[]},"result":%s}`, validResult)},
		{"unknown result member", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[%s],"unexpected":true}}`, row)},
		{"data case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"Data":[%s]}}`, row)},
		{"duplicate data ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[],"data":[%s]}}`, row)},
		{"unknown transfer member", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[%s]}}`, rowUnknown)},
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

func TestHeliusResponseRejectsInvalidOfficialTransferValues(t *testing.T) {
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
		{"missing slot", strings.Replace(row, `"slot":123,`, "", 1)},
		{"missing UI amount", strings.Replace(row, `"uiAmount":"0.000000042",`, "", 1)},
		{"missing inner instruction index", strings.Replace(row, `,"innerInstructionIdx":null`, "", 1)},
		{"negative raw amount", strings.Replace(row, `"amount":"42"`, `"amount":"-42"`, 1)},
		{"fractional raw amount", strings.Replace(row, `"amount":"42"`, `"amount":"4.2"`, 1)},
		{"invalid UI amount", strings.Replace(row, `"uiAmount":"0.000000042"`, `"uiAmount":"NaN"`, 1)},
		{"unknown transfer type", strings.Replace(row, `"type":"transfer"`, `"type":"airdrop"`, 1)},
		{"both owners null", strings.Replace(row, `"fromUserAccount":"from","toUserAccount":"to"`, `"fromUserAccount":null,"toUserAccount":null`, 1)},
		{"null optional token account", strings.Replace(row, `"mint":`, `"fromTokenAccount":null,"mint":`, 1)},
		{"partial token fee", strings.Replace(row, `"confirmationStatus":`, `"feeAmount":"1","confirmationStatus":`, 1)},
		{"null pagination token", row},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := fmt.Sprintf(`{"data":[%s]}`, tc.row)
			if tc.name == "null pagination token" {
				result = fmt.Sprintf(`{"data":[%s],"paginationToken":null}`, tc.row)
			}
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
	rowUnknown := strings.Replace(row, `"metadata":`, `"unexpected":true,"metadata":`, 1)
	rowHashAlias := strings.Replace(row, `"hash":`, `"Hash":`, 1)
	rowDuplicateHash := strings.Replace(row, `"hash":`, `"hash":"0xdead","hash":`, 1)
	rowRawUnknown := strings.Replace(row, `"decimal":"0x12"`, `"decimal":"0x12","unexpected":true`, 1)
	rowRawAlias := strings.Replace(row, `"value":"0x1"`, `"Value":"0x1"`, 1)
	rowRawDuplicate := strings.Replace(row, `"value":"0x1"`, `"value":"0x2","value":"0x1"`, 1)
	rowMetadataUnknown := strings.Replace(row, `"blockTimestamp":"2026-07-29T01:01:00Z"`, `"blockTimestamp":"2026-07-29T01:01:00Z","unexpected":true`, 1)
	rowTimestampAlias := strings.Replace(row, `"blockTimestamp":`, `"BlockTimestamp":`, 1)
	rowTimestampDuplicate := strings.Replace(row, `"blockTimestamp":`, `"blockTimestamp":"2020-01-01T00:00:00Z","blockTimestamp":`, 1)

	tests := []struct {
		name    string
		payload string
	}{
		{"wrong response id", fmt.Sprintf(`{"jsonrpc":"2.0","id":2,"result":%s}`, validResult)},
		{"missing response id", fmt.Sprintf(`{"jsonrpc":"2.0","result":%s}`, validResult)},
		{"wrong version", fmt.Sprintf(`{"jsonrpc":"1.0","id":1,"result":%s}`, validResult)},
		{"unknown envelope member", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":%s,"unexpected":true}`, validResult)},
		{"result case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"Result":%s}`, validResult)},
		{"result case collision", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[]},"Result":%s}`, validResult)},
		{"duplicate response id ending expected", fmt.Sprintf(`{"jsonrpc":"2.0","id":2,"id":1,"result":%s}`, validResult)},
		{"duplicate result ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[]},"result":%s}`, validResult)},
		{"unknown result member", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s],"unexpected":true}}`, row)},
		{"transfers case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"Transfers":[%s]}}`, row)},
		{"duplicate transfers ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[],"transfers":[%s]}}`, row)},
		{"unknown transfer member", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowUnknown)},
		{"transfer hash case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowHashAlias)},
		{"duplicate transfer hash", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowDuplicateHash)},
		{"unknown raw contract member", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowRawUnknown)},
		{"raw value case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowRawAlias)},
		{"duplicate raw value", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowRawDuplicate)},
		{"unknown metadata member", fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[%s]}}`, rowMetadataUnknown)},
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
		name   string
		row    string
		result string
	}{
		{"missing block number", strings.Replace(row, `"blockNum":"0xabc",`, "", 1), ""},
		{"invalid block number", strings.Replace(row, `"blockNum":"0xabc"`, `"blockNum":"latest"`, 1), ""},
		{"invalid transaction hash", strings.Replace(row, `"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"`, `"hash":"0x1234"`, 1), ""},
		{"invalid sender", strings.Replace(row, `"from":"0x1111111111111111111111111111111111111111"`, `"from":"0x1234"`, 1), ""},
		{"invalid recipient", strings.Replace(row, `"to":"0x2222222222222222222222222222222222222222"`, `"to":"0x1234"`, 1), ""},
		{"unsupported category", strings.Replace(row, `"category":"external"`, `"category":"erc721"`, 1), ""},
		{"missing raw decimal", strings.Replace(row, `,"decimal":"0x12"`, "", 1), ""},
		{"invalid raw value", strings.Replace(row, `"value":"0x1"`, `"value":"-1"`, 1), ""},
		{"zero raw value excluded by request", strings.Replace(row, `"value":"0x1"`, `"value":"0x0"`, 1), ""},
		{"decimal exceeds ERC20 range", strings.Replace(row, `"decimal":"0x12"`, `"decimal":"0x100"`, 1), ""},
		{"native row with token contract", strings.Replace(row, `"address":null`, `"address":"0x3333333333333333333333333333333333333333"`, 1), ""},
		{"token row without contract", strings.Replace(row, `"category":"external"`, `"category":"erc20"`, 1), ""},
		{"invalid block timestamp", strings.Replace(row, `"blockTimestamp":"2026-07-29T01:01:00Z"`, `"blockTimestamp":"yesterday"`, 1), ""},
		{"value must be numeric", strings.Replace(row, `"asset":"ETH"`, `"value":"1","asset":"ETH"`, 1), ""},
		{"erc721 token id must be string", strings.Replace(row, `"asset":"ETH"`, `"erc721TokenId":{},"asset":"ETH"`, 1), ""},
		{"erc1155 metadata must be array", strings.Replace(row, `"asset":"ETH"`, `"erc1155Metadata":{},"asset":"ETH"`, 1), ""},
		{"erc721 token id is inapplicable", strings.Replace(row, `"asset":"ETH"`, `"erc721TokenId":"0x1","asset":"ETH"`, 1), ""},
		{"erc1155 metadata is inapplicable", strings.Replace(row, `"asset":"ETH"`, `"erc1155Metadata":[],"asset":"ETH"`, 1), ""},
		{"generic token id is inapplicable", strings.Replace(row, `"asset":"ETH"`, `"tokenId":"1","asset":"ETH"`, 1), ""},
		{"trace address must be string", strings.Replace(row, `"asset":"ETH"`, `"typeTraceAddress":7,"asset":"ETH"`, 1), ""},
		{"null page key", row, `{"transfers":[%s],"pageKey":null}`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := fmt.Sprintf(`{"transfers":[%s]}`, tc.row)
			if tc.result != "" {
				result = fmt.Sprintf(tc.result, tc.row)
			}
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

	payload := `{"jsonrpc":"2.0","id":1,"result":{"transfers":[` +
		`{"blockNum":"0xabc","uniqueId":"0xcreate:external",` +
		`"hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"from":"0x1111111111111111111111111111111111111111","to":null,` +
		`"value":1,"erc721TokenId":null,"erc1155Metadata":null,"tokenId":null,` +
		`"asset":"ETH","category":"external","typeTraceAddress":null,` +
		`"rawContract":{"value":"0x1","address":null,"decimal":"0x12"},"metadata":null},` +
		`{"blockNum":"0xabd","uniqueId":"0xtoken:log:1",` +
		`"hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",` +
		`"from":"0x2222222222222222222222222222222222222222",` +
		`"to":"0x1111111111111111111111111111111111111111",` +
		`"asset":"USDC","category":"erc20",` +
		`"rawContract":{"value":"0x2","address":"0x3333333333333333333333333333333333333333","decimal":"0x6"},` +
		`"metadata":{"blockTimestamp":"2026-07-29T01:01:00.123Z"}}` +
		`],"pageKey":"page-2"}}`
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
		{"unknown envelope member", fmt.Sprintf(`[{"jsonrpc":"2.0","id":1,"result":%s,"unexpected":true}]`, block)},
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
		`{"jsonrpc":"2.0","id":2,"result":{"number":"0xabd",` +
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

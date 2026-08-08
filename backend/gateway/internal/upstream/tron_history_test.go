package upstream

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const (
	tronHistoryAddress = "TJmmqjb1DK9TTZbQXzRQ2AuA94z4gKAPFh"
	tronHistoryTxID    = "9e9a6aae39bd653da37988c5fe11332dc2a130acf6588d7021785d767655e621"
	tronInternalID     = "785b0f553c641312a14d1565bc5eac0ce7d9e46e4c06c5a27c3a6cb9a131a681"
)

func TestTronHistoryResponsesRejectAmbiguousProviderJSON(t *testing.T) {
	t.Parallel()

	trc20Row := `{"transaction_id":"` + tronHistoryTxID + `",` +
		`"token_info":{"symbol":"USDT","address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","decimals":6,"name":"Tether USD"},` +
		`"block_timestamp":1700000000000,"from":"TQguVRm3tDmZG7AeZ47Mk6qi6GTF1ZDqkZ",` +
		`"to":"` + tronHistoryAddress + `","type":"Transfer","value":"1000000"}`
	nativeRow := `{"ret":[{"contractRet":"SUCCESS","fee":0}],"txID":"` + tronHistoryTxID + `",` +
		`"block_timestamp":1700000000000,"raw_data":{"contract":[{"parameter":{"value":{` +
		`"amount":42,"owner_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa",` +
		`"to_address":"41608f8da72479edc7dd921e4c30bb7e7cddbe722e"},` +
		`"type_url":"type.googleapis.com/protocol.TransferContract"},"type":"TransferContract"}]}}`
	internalRow := `{"internal_tx_id":"` + tronInternalID + `","data":{"note":"call",` +
		`"rejected":false,"call_value":{"_":42}},"block_timestamp":1700000000000,` +
		`"to_address":"41608f8da72479edc7dd921e4c30bb7e7cddbe722e","tx_id":"` + tronHistoryTxID + `",` +
		`"from_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa"}`

	tests := []struct {
		name    string
		path    string
		payload string
		call    func(*Tron) error
	}{
		{"trc20 data alias collision", "/v1/accounts/", `{"Data":[],"data":[` + trc20Row + `],"success":true}`, func(client *Tron) error {
			_, err := client.TRC20Transfers(context.Background(), tronHistoryAddress, 20)
			return err
		}},
		{"trc20 duplicate data ending valid", "/v1/accounts/", `{"data":[],"data":[` + trc20Row + `],"success":true}`, func(client *Tron) error {
			_, err := client.TRC20Transfers(context.Background(), tronHistoryAddress, 20)
			return err
		}},
		{"trc20 false success", "/v1/accounts/", `{"data":[` + trc20Row + `],"success":false}`, func(client *Tron) error {
			_, err := client.TRC20Transfers(context.Background(), tronHistoryAddress, 20)
			return err
		}},
		{"trc20 duplicate value", "/v1/accounts/", `{"data":[` + strings.Replace(trc20Row, `"value":"1000000"`, `"value":"1","value":"1000000"`, 1) + `],"success":true}`, func(client *Tron) error {
			_, err := client.TRC20Transfers(context.Background(), tronHistoryAddress, 20)
			return err
		}},
		{"trc20 token info alias", "/v1/accounts/", `{"data":[` + strings.Replace(trc20Row, `"symbol":"USDT"`, `"Symbol":"FAKE","symbol":"USDT"`, 1) + `],"success":true}`, func(client *Tron) error {
			_, err := client.TRC20Transfers(context.Background(), tronHistoryAddress, 20)
			return err
		}},
		{"native duplicate amount", "/v1/accounts/", `{"data":[` + strings.Replace(nativeRow, `"amount":42`, `"amount":1,"amount":42`, 1) + `],"success":true}`, func(client *Tron) error {
			_, err := client.NativeTransactions(context.Background(), tronHistoryAddress, 20)
			return err
		}},
		{"native contract type alias", "/v1/accounts/", `{"data":[` + strings.Replace(nativeRow, `"type":"TransferContract"`, `"Type":"TriggerSmartContract","type":"TransferContract"`, 1) + `],"success":true}`, func(client *Tron) error {
			_, err := client.NativeTransactions(context.Background(), tronHistoryAddress, 20)
			return err
		}},
		{"native contract type URL mismatch", "/v1/accounts/", `{"data":[` + strings.Replace(nativeRow, `type.googleapis.com/protocol.TransferContract`, `type.googleapis.com/protocol.TriggerSmartContract`, 1) + `],"success":true}`, func(client *Tron) error {
			_, err := client.NativeTransactions(context.Background(), tronHistoryAddress, 20)
			return err
		}},
		{"internal duplicate scalar", "/v1/accounts/", `{"data":[` + strings.Replace(internalRow, `"_":42`, `"_":1,"_":42`, 1) + `],"success":true}`, func(client *Tron) error {
			_, err := client.InternalTransactions(context.Background(), tronHistoryAddress, 20)
			return err
		}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if !strings.HasPrefix(r.URL.Path, tc.path) {
					t.Errorf("unexpected path: %s", r.URL.Path)
					http.NotFound(w, r)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				_, _ = fmt.Fprint(w, tc.payload)
			}))
			defer server.Close()

			if err := tc.call(NewTron(server.URL, server.Client(), time.Second)); err == nil {
				t.Fatal("ambiguous TronGrid history response must fail closed")
			}
		})
	}
}

func TestTronHistoryAllowsAdditiveProviderFields(t *testing.T) {
	t.Parallel()

	trc20 := `{"data":[{"transaction_id":"` + tronHistoryTxID + `",` +
		`"token_info":{"symbol":"USDT","address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",` +
		`"decimals":6,"name":"Tether USD","futureTokenField":{}},` +
		`"block_timestamp":1700000000000,"from":"TQguVRm3tDmZG7AeZ47Mk6qi6GTF1ZDqkZ",` +
		`"to":"` + tronHistoryAddress + `","type":"Transfer","value":"1000000","futureRowField":[]},{}],` +
		`"success":true,"futureEnvelopeField":1,"meta":{"page_size":1,"futureMetaField":true,` +
		`"links":{"next":"https://example.test/next","futureLinkField":null}}}`
	trc20Rows, err := decodeTronTRC20History([]byte(trc20))
	if err != nil || len(trc20Rows) != 1 || trc20Rows[0].Value != "1000000" {
		t.Fatalf("additive TRC-20 fields broke history: rows=%#v err=%v", trc20Rows, err)
	}

	native := `{"data":[{"ret":[{"contractRet":"SUCCESS","fee":0,"futureReceipt":true}],` +
		`"txID":"` + tronHistoryTxID + `","block_timestamp":1700000000000,"futureRow":{},` +
		`"raw_data":{"futureRaw":1,"contract":[{"Permission_id":2,"permission_id":2,"futureContract":null,` +
		`"parameter":{"futureParameter":[],"value":{"amount":42,` +
		`"owner_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa",` +
		`"to_address":"41608f8da72479edc7dd921e4c30bb7e7cddbe722e","futureValue":true},` +
		`"type_url":"type.googleapis.com/protocol.TransferContract"},"type":"TransferContract"}]}},{}],` +
		`"success":true,"futureEnvelope":[]}`
	nativeRows, err := decodeTronNativeHistory([]byte(native))
	if err != nil || len(nativeRows) != 1 || nativeRows[0].Amount != "42" {
		t.Fatalf("additive native fields broke history: rows=%#v err=%v", nativeRows, err)
	}

	internal := `{"data":[{"internal_tx_id":"` + tronInternalID + `","futureRow":1,` +
		`"data":{"note":"call","rejected":false,"call_value":{"_":42,"futureScalar":true},"futureData":{}},` +
		`"block_timestamp":1700000000000,"to_address":"41608f8da72479edc7dd921e4c30bb7e7cddbe722e",` +
		`"tx_id":"` + tronHistoryTxID + `","from_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa"},{}],` +
		`"success":true,"futureEnvelope":{}}`
	internalRows, err := decodeTronInternalHistory([]byte(internal))
	if err != nil || len(internalRows) != 1 || internalRows[0].Amount != "42" {
		t.Fatalf("additive internal fields broke history: rows=%#v err=%v", internalRows, err)
	}
}

func TestTronHistoryRowsRejectInvalidFinancialValues(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		path    string
		payload string
		call    func(*Tron) error
	}{
		{
			name: "trc20 negative amount and short transaction id",
			path: "/v1/accounts/",
			payload: `{"data":[{"transaction_id":"short","token_info":{"symbol":"USDT",` +
				`"address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","decimals":6},` +
				`"block_timestamp":1700000000000,"from":"TQguVRm3tDmZG7AeZ47Mk6qi6GTF1ZDqkZ",` +
				`"to":"` + tronHistoryAddress + `","type":"Transfer","value":"-1"}],"success":true}`,
			call: func(client *Tron) error {
				_, err := client.TRC20Transfers(context.Background(), tronHistoryAddress, 20)
				return err
			},
		},
		{
			name: "native fractional amount",
			path: "/v1/accounts/",
			payload: `{"data":[{"ret":[{"contractRet":"SUCCESS"}],"txID":"` + tronHistoryTxID + `",` +
				`"block_timestamp":1700000000000,"raw_data":{"contract":[{"parameter":{"value":{` +
				`"amount":1.5,"owner_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa",` +
				`"to_address":"41608f8da72479edc7dd921e4c30bb7e7cddbe722e"}},"type":"TransferContract"}]}}],"success":true}`,
			call: func(client *Tron) error {
				_, err := client.NativeTransactions(context.Background(), tronHistoryAddress, 20)
				return err
			},
		},
		{
			name: "internal negative amount",
			path: "/v1/accounts/",
			payload: `{"data":[{"internal_tx_id":"` + tronInternalID + `","data":{"rejected":false,` +
				`"call_value":{"_":-1}},"block_timestamp":1700000000000,` +
				`"to_address":"41608f8da72479edc7dd921e4c30bb7e7cddbe722e","tx_id":"` + tronHistoryTxID + `",` +
				`"from_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa"}],"success":true}`,
			call: func(client *Tron) error {
				_, err := client.InternalTransactions(context.Background(), tronHistoryAddress, 20)
				return err
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = fmt.Fprint(w, tc.payload)
			}))
			defer server.Close()
			if err := tc.call(NewTron(server.URL, server.Client(), time.Second)); err == nil {
				t.Fatal("invalid TronGrid financial value must fail closed")
			}
		})
	}
}

func TestTronHistoryOfficialShapesAndEventCardinality(t *testing.T) {
	t.Parallel()

	const other = "TQguVRm3tDmZG7AeZ47Mk6qi6GTF1ZDqkZ"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query()
		if query.Get("limit") != "20" || query.Get("only_confirmed") != "true" ||
			query.Get("order_by") != "block_timestamp,desc" {
			t.Errorf("history query is not deterministic and confirmed-only: %s", r.URL.RawQuery)
		}
		w.Header().Set("Content-Type", "application/json")
		meta := `,"meta":{"at":1700000000001,"page_size":1,"fingerprint":"next-page",` +
			`"links":{"next":"https://api.trongrid.io/v1/accounts/redacted?fingerprint=next-page"}}`
		switch {
		case strings.HasSuffix(r.URL.Path, "/transactions/trc20"):
			_, _ = fmt.Fprintf(w, `{"data":[{"transaction_id":%q,"token_info":{"symbol":"USDT",`+
				`"address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","decimals":6,"name":"Tether USD"},`+
				`"block_timestamp":1700000000000,"from":%q,"to":%q,"type":"Transfer",`+
				`"value":"1000000"}],"success":true%s}`, tronHistoryTxID, other, tronHistoryAddress, meta)
		case strings.HasSuffix(r.URL.Path, "/internal-transactions"):
			_, _ = fmt.Fprintf(w, `{"data":[{"internal_tx_id":%q,"data":{"note":"call",`+
				`"rejected":false,"call_value":{"_":42},"call_token_value":{"_":"7"},"token_id":"1002000"},`+
				`"block_timestamp":1700000000000,"to_address":"41608f8da72479edc7dd921e4c30bb7e7cddbe722e",`+
				`"tx_id":%q,"from_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa"}],`+
				`"success":true%s}`, tronInternalID, tronHistoryTxID, meta)
		case strings.HasSuffix(r.URL.Path, "/transactions"):
			_, _ = fmt.Fprintf(w, `{"data":[{"ret":[{"contractRet":"SUCCESS","fee":0}],`+
				`"signature":["00"],"txID":%q,"net_usage":1,"raw_data_hex":"00","net_fee":0,`+
				`"energy_usage":0,"energy_fee":0,"energy_usage_total":0,"internal_transactions":[],`+
				`"blockNumber":1,"block_timestamp":1700000000000,"raw_data":{"ref_block_bytes":"00",`+
				`"ref_block_hash":"00","expiration":1700000060000,"timestamp":1700000000000,"contract":[`+
				`{"parameter":{"value":{"amount":42,"owner_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa",`+
				`"to_address":"41608f8da72479edc7dd921e4c30bb7e7cddbe722e"},`+
				`"type_url":"type.googleapis.com/protocol.TransferContract"},"type":"TransferContract"},`+
				`{"parameter":{"value":{"owner_address":"4178d80a0c4f4106c1119c20e69e852c256c02ddaa"},`+
				`"type_url":"type.googleapis.com/protocol.TriggerSmartContract"},"type":"TriggerSmartContract"}]}}],`+
				`"success":true%s}`, tronHistoryTxID, meta)
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := NewTron(server.URL, server.Client(), time.Second)
	trc20, err := client.TRC20Transfers(context.Background(), tronHistoryAddress, 20)
	if err != nil || len(trc20) != 1 || trc20[0].Value != "1000000" || trc20[0].Decimals != 6 {
		t.Fatalf("official TRC-20 shape failed: transfers=%+v err=%v", trc20, err)
	}
	native, err := client.NativeTransactions(context.Background(), tronHistoryAddress, 20)
	if err != nil || len(native) != 1 || native[0].Amount != "42" || native[0].ContractIndex != 0 ||
		native[0].Status != ExecutionConfirmed {
		t.Fatalf("official native shape failed: transfers=%+v err=%v", native, err)
	}
	internal, err := client.InternalTransactions(context.Background(), tronHistoryAddress, 20)
	if err != nil || len(internal) != 2 || internal[0].Amount != "42" || internal[0].TokenID != "" ||
		internal[1].Amount != "7" || internal[1].TokenID != "1002000" || internal[1].AssetIndex != 1 {
		t.Fatalf("dual-asset internal shape failed: transfers=%+v err=%v", internal, err)
	}
}

func TestTronTRC20AuthorizationIsNotAssetHistory(t *testing.T) {
	t.Parallel()
	payload := `{"data":[{"transaction_id":"` + tronHistoryTxID + `",` +
		`"token_info":{"symbol":"USDT","address":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","decimals":6},` +
		`"block_timestamp":1700000000000,"from":"TQguVRm3tDmZG7AeZ47Mk6qi6GTF1ZDqkZ",` +
		`"to":"` + tronHistoryAddress + `","type":"Approval","value":"1000000"}],"success":true}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = fmt.Fprint(w, payload)
	}))
	defer server.Close()
	transfers, err := NewTron(server.URL, server.Client(), time.Second).
		TRC20Transfers(context.Background(), tronHistoryAddress, 20)
	if err != nil || len(transfers) != 0 {
		t.Fatalf("authorization must be ignored, transfers=%+v err=%v", transfers, err)
	}
}

func TestTronHistoryIgnoresNonSemanticPaginationMeta(t *testing.T) {
	t.Parallel()
	for _, payload := range []string{
		`{"data":[],"success":true,"meta":{"page_size":1,"Page_size":2}}`,
		`{"data":[],"success":true,"meta":{"fingerprint":"a","fingerprint":"b"}}`,
		`{"data":[],"success":true,"meta":{"links":{"next":"https://example.test","Next":"bad"}}}`,
		`{"data":[],"success":true,"meta":{"page_size":1.5}}`,
		`{"data":[],"success":true,"meta":"provider-defined"}`,
	} {
		rows, err := decodeTronHistoryEnvelope([]byte(payload))
		if err != nil || rows == nil || len(rows) != 0 {
			t.Fatalf("non-semantic pagination metadata broke history: rows=%#v err=%v payload=%s", rows, err, payload)
		}
	}
}

package upstream

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"strings"
	"unicode/utf8"
)

func decodeTronHistoryEnvelope(data []byte) ([]json.RawMessage, error) {
	fields, err := decodeExtensibleJSONObject(data, "data", "success")
	if err != nil {
		return nil, err
	}
	var success *bool
	if err := json.Unmarshal(fields["success"], &success); err != nil || success == nil || !*success {
		return nil, fmt.Errorf("TronGrid history response was not successful")
	}
	var rows []json.RawMessage
	if err := json.Unmarshal(fields["data"], &rows); err != nil || rows == nil {
		return nil, fmt.Errorf("invalid TronGrid history data")
	}
	return rows, nil
}

func decodeTronTRC20History(data []byte) ([]TRC20Transfer, error) {
	rows, err := decodeTronHistoryEnvelope(data)
	if err != nil {
		return nil, err
	}
	transfers := make([]TRC20Transfer, 0, len(rows))
	malformed := false
	for _, raw := range rows {
		transfer, include, err := decodeTronTRC20Transfer(raw)
		if err != nil {
			malformed = true
			continue
		}
		if include {
			transfers = append(transfers, transfer)
		}
	}
	if malformed && len(transfers) == 0 {
		return nil, fmt.Errorf("TronGrid TRC-20 page has no valid transfer rows")
	}
	return transfers, nil
}

func decodeTronTRC20Transfer(raw json.RawMessage) (TRC20Transfer, bool, error) {
	fields, err := decodeExtensibleJSONObject(
		raw, "transaction_id", "token_info", "block_timestamp", "from", "to", "type", "value",
	)
	if err != nil {
		return TRC20Transfer{}, false, err
	}
	typeName, err := requiredTronString(fields, "type")
	if err != nil || !validTronText(typeName, 64, false) {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token event type")
	}
	// The endpoint also returns approvals and NFT events. They are not asset
	// movements and must not be mislabeled as fungible token transfers.
	if typeName != "Transfer" {
		return TRC20Transfer{}, false, nil
	}
	txID, err := requiredTronString(fields, "transaction_id")
	if err != nil || !tronTransactionIDPattern.MatchString(txID) {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token transaction id")
	}
	from, err := requiredTronString(fields, "from")
	if err != nil || !validTronAddress(from) {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token sender")
	}
	to, err := requiredTronString(fields, "to")
	if err != nil || !validTronAddress(to) {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token recipient")
	}
	value, err := requiredTronString(fields, "value")
	if err != nil || !validTronUnsignedDecimal(value, 256) {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token value")
	}
	timestamp, err := requiredTronInt64(fields, "block_timestamp")
	if err != nil || timestamp <= 0 {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token timestamp")
	}
	tokenRaw, ok := fields["token_info"]
	if !ok {
		return TRC20Transfer{}, false, fmt.Errorf("missing TronGrid token info")
	}
	token, err := decodeExtensibleJSONObject(tokenRaw, "symbol", "address", "decimals")
	if err != nil {
		return TRC20Transfer{}, false, err
	}
	symbol, err := requiredTronString(token, "symbol")
	if err != nil || !validTronText(symbol, 128, true) {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token symbol")
	}
	contract, err := requiredTronString(token, "address")
	if err != nil || !validTronAddress(contract) {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token contract")
	}
	decimals, err := requiredTronInt64(token, "decimals")
	if err != nil || decimals < 0 || decimals > 255 {
		return TRC20Transfer{}, false, fmt.Errorf("invalid TronGrid token decimals")
	}
	return TRC20Transfer{
		TransactionID: txID, From: from, To: to, Value: value,
		BlockTimestamp: timestamp, Symbol: symbol, Decimals: int(decimals), Contract: contract,
	}, true, nil
}

func decodeTronNativeHistory(data []byte) ([]NativeTransfer, error) {
	rows, err := decodeTronHistoryEnvelope(data)
	if err != nil {
		return nil, err
	}
	var transfers []NativeTransfer
	malformed := false
	for _, raw := range rows {
		row, err := decodeTronNativeTransaction(raw)
		if err != nil {
			malformed = true
			continue
		}
		transfers = append(transfers, row...)
	}
	if malformed && len(transfers) == 0 {
		return nil, fmt.Errorf("TronGrid native page has no valid transfer rows")
	}
	return transfers, nil
}

func decodeTronNativeTransaction(raw json.RawMessage) ([]NativeTransfer, error) {
	fields, err := decodeExtensibleJSONObject(
		raw,
		"ret", "txID", "block_timestamp", "raw_data",
	)
	if err != nil {
		return nil, err
	}
	txID, err := requiredTronString(fields, "txID")
	if err != nil || !tronTransactionIDPattern.MatchString(txID) {
		return nil, fmt.Errorf("invalid TronGrid native transaction id")
	}
	timestamp, err := requiredTronInt64(fields, "block_timestamp")
	if err != nil || timestamp <= 0 {
		return nil, fmt.Errorf("invalid TronGrid native timestamp")
	}
	status, err := decodeTronNativeStatus(fields["ret"])
	if err != nil {
		return nil, err
	}
	rawData, ok := fields["raw_data"]
	if !ok {
		return nil, fmt.Errorf("missing TronGrid raw transaction")
	}
	rawFields, err := decodeExtensibleJSONObject(rawData, "contract")
	if err != nil {
		return nil, err
	}
	var contracts []json.RawMessage
	if err := json.Unmarshal(rawFields["contract"], &contracts); err != nil || contracts == nil {
		return nil, fmt.Errorf("invalid TronGrid contract list")
	}
	transfers := make([]NativeTransfer, 0, len(contracts))
	for index, contractRaw := range contracts {
		contract, err := decodeExtensibleJSONObject(contractRaw, "parameter", "type")
		if err != nil {
			return nil, err
		}
		contractType, err := requiredTronString(contract, "type")
		if err != nil || !validTronText(contractType, 128, false) {
			return nil, fmt.Errorf("invalid TronGrid contract type")
		}
		if contractType != "TransferContract" && contractType != "TransferAssetContract" {
			continue
		}
		parameterRaw, ok := contract["parameter"]
		if !ok {
			return nil, fmt.Errorf("missing TronGrid contract parameter")
		}
		parameter, err := decodeExtensibleJSONObject(parameterRaw, "value", "type_url")
		if err != nil {
			return nil, err
		}
		valueRaw, ok := parameter["value"]
		if !ok {
			return nil, fmt.Errorf("missing TronGrid contract value")
		}
		if typeURLRaw, present := parameter["type_url"]; present {
			typeURL, err := tronJSONString(typeURLRaw)
			if err != nil || typeURL != "type.googleapis.com/protocol."+contractType {
				return nil, fmt.Errorf("mismatched TronGrid contract type URL")
			}
		}
		value, err := decodeExtensibleJSONObject(valueRaw, "amount", "owner_address", "to_address", "asset_name")
		if err != nil {
			return nil, err
		}
		amount, err := requiredTronUintString(value, "amount", 63)
		if err != nil {
			return nil, fmt.Errorf("invalid TronGrid native amount")
		}
		owner, err := requiredTronString(value, "owner_address")
		if err != nil || !validTronAddress(owner) {
			return nil, fmt.Errorf("invalid TronGrid native sender")
		}
		to, err := requiredTronString(value, "to_address")
		if err != nil || !validTronAddress(to) {
			return nil, fmt.Errorf("invalid TronGrid native recipient")
		}
		tokenID := ""
		if contractType == "TransferAssetContract" {
			tokenID, err = requiredTronString(value, "asset_name")
			if err != nil || !validTronUnsignedDecimal(tokenID, 64) {
				return nil, fmt.Errorf("invalid TronGrid TRC-10 id")
			}
		} else if _, present := value["asset_name"]; present {
			return nil, fmt.Errorf("TRX transfer unexpectedly carries an asset id")
		}
		transfers = append(transfers, NativeTransfer{
			TxID: txID, Owner: owner, To: to, Amount: amount, TokenID: tokenID,
			ContractIndex: index, BlockTimestamp: timestamp, Status: status,
		})
	}
	return transfers, nil
}

func decodeTronNativeStatus(raw json.RawMessage) (ExecutionStatus, error) {
	if len(bytes.TrimSpace(raw)) == 0 {
		return ExecutionUnknown, nil
	}
	var rows []json.RawMessage
	if err := json.Unmarshal(raw, &rows); err != nil || rows == nil {
		return ExecutionUnknown, fmt.Errorf("invalid TronGrid receipt list")
	}
	if len(rows) == 0 {
		return ExecutionUnknown, nil
	}
	status := ExecutionConfirmed
	for _, raw := range rows {
		fields, err := decodeExtensibleJSONObject(raw, "contractRet")
		if err != nil {
			return ExecutionUnknown, err
		}
		result, err := requiredTronString(fields, "contractRet")
		result = strings.ToUpper(strings.TrimSpace(result))
		if err != nil {
			return ExecutionUnknown, fmt.Errorf("missing TronGrid receipt result")
		}
		if _, known := tronReceiptResults[result]; !known {
			return ExecutionUnknown, fmt.Errorf("unknown TronGrid receipt result")
		}
		if result != "SUCCESS" {
			status = ExecutionFailed
		}
	}
	return status, nil
}

func decodeTronInternalHistory(data []byte) ([]InternalTransfer, error) {
	rows, err := decodeTronHistoryEnvelope(data)
	if err != nil {
		return nil, err
	}
	var transfers []InternalTransfer
	malformed := false
	for _, raw := range rows {
		row, err := decodeTronInternalTransaction(raw)
		if err != nil {
			malformed = true
			continue
		}
		transfers = append(transfers, row...)
	}
	if malformed && len(transfers) == 0 {
		return nil, fmt.Errorf("TronGrid internal page has no valid transfer rows")
	}
	return transfers, nil
}

func decodeTronInternalTransaction(raw json.RawMessage) ([]InternalTransfer, error) {
	fields, err := decodeExtensibleJSONObject(
		raw, "internal_tx_id", "data", "block_timestamp", "to_address", "tx_id", "from_address",
	)
	if err != nil {
		return nil, err
	}
	txID, err := requiredTronString(fields, "tx_id")
	if err != nil || !tronTransactionIDPattern.MatchString(txID) {
		return nil, fmt.Errorf("invalid TronGrid internal parent id")
	}
	internalID, err := requiredTronString(fields, "internal_tx_id")
	if err != nil || !tronTransactionIDPattern.MatchString(internalID) {
		return nil, fmt.Errorf("invalid TronGrid internal trace id")
	}
	from, err := requiredTronString(fields, "from_address")
	if err != nil || !validTronAddress(from) {
		return nil, fmt.Errorf("invalid TronGrid internal sender")
	}
	to, err := requiredTronString(fields, "to_address")
	if err != nil || !validTronAddress(to) {
		return nil, fmt.Errorf("invalid TronGrid internal recipient")
	}
	timestamp, err := requiredTronInt64(fields, "block_timestamp")
	if err != nil || timestamp <= 0 {
		return nil, fmt.Errorf("invalid TronGrid internal timestamp")
	}
	dataRaw, ok := fields["data"]
	if !ok {
		return nil, fmt.Errorf("missing TronGrid internal data")
	}
	data, err := decodeExtensibleJSONObject(dataRaw, "rejected", "call_value", "call_token_value", "token_id")
	if err != nil {
		return nil, err
	}
	status := ExecutionUnknown
	if rejectedRaw, ok := data["rejected"]; ok {
		var rejected *bool
		if err := json.Unmarshal(rejectedRaw, &rejected); err != nil || rejected == nil {
			return nil, fmt.Errorf("invalid TronGrid rejected flag")
		}
		if *rejected {
			status = ExecutionFailed
		} else {
			status = ExecutionConfirmed
		}
	}
	callValue, err := optionalTronScalar(data["call_value"], 63)
	if err != nil {
		return nil, fmt.Errorf("invalid TronGrid internal TRX value")
	}
	tokenValue, err := optionalTronScalar(data["call_token_value"], 63)
	if err != nil {
		return nil, fmt.Errorf("invalid TronGrid internal token value")
	}
	tokenID, err := optionalTronScalar(data["token_id"], 64)
	if err != nil {
		return nil, fmt.Errorf("invalid TronGrid internal token id")
	}
	if tokenValue != "" && tokenValue != "0" && (tokenID == "" || tokenID == "0") {
		return nil, fmt.Errorf("missing TronGrid internal token id")
	}
	base := InternalTransfer{
		TxID: txID, InternalTxID: internalID, From: from, To: to,
		BlockTimestamp: timestamp, Status: status,
	}
	transfers := make([]InternalTransfer, 0, 2)
	if callValue != "" && callValue != "0" {
		transfer := base
		transfer.Amount = callValue
		transfers = append(transfers, transfer)
	}
	if tokenValue != "" && tokenValue != "0" {
		transfer := base
		transfer.Amount = tokenValue
		transfer.TokenID = tokenID
		transfer.AssetIndex = 1
		transfers = append(transfers, transfer)
	}
	return transfers, nil
}

func requiredTronString(fields map[string]json.RawMessage, key string) (string, error) {
	raw, ok := fields[key]
	if !ok {
		return "", fmt.Errorf("missing TronGrid field %s", key)
	}
	return tronJSONString(raw)
}

func tronJSONString(raw json.RawMessage) (string, error) {
	var value *string
	if err := json.Unmarshal(raw, &value); err != nil || value == nil {
		return "", fmt.Errorf("expected JSON string")
	}
	return *value, nil
}

func requiredTronInt64(fields map[string]json.RawMessage, key string) (int64, error) {
	raw, ok := fields[key]
	if !ok {
		return 0, fmt.Errorf("missing TronGrid field %s", key)
	}
	value, err := tronJSONUint(raw, 63)
	if err != nil {
		return 0, err
	}
	return value.Int64(), nil
}

func requiredTronUintString(fields map[string]json.RawMessage, key string, bits int) (string, error) {
	raw, ok := fields[key]
	if !ok {
		return "", fmt.Errorf("missing TronGrid field %s", key)
	}
	value, err := tronJSONUint(raw, bits)
	if err != nil {
		return "", err
	}
	return value.String(), nil
}

func tronJSONUint(raw json.RawMessage, bits int) (*big.Int, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
		return nil, fmt.Errorf("missing unsigned integer")
	}
	var encoded string
	if trimmed[0] == '"' {
		if err := json.Unmarshal(trimmed, &encoded); err != nil {
			return nil, err
		}
	} else {
		encoded = string(trimmed)
	}
	if !validTronUnsignedDecimal(encoded, bits) {
		return nil, fmt.Errorf("invalid unsigned integer")
	}
	value, _ := new(big.Int).SetString(encoded, 10)
	return value, nil
}

func optionalTronScalar(raw json.RawMessage, bits int) (string, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
		return "", nil
	}
	if trimmed[0] == '{' {
		fields, err := decodeExtensibleJSONObject(trimmed, "_")
		if err != nil {
			return "", err
		}
		valueRaw, ok := fields["_"]
		if !ok {
			return "", fmt.Errorf("missing scalar value")
		}
		trimmed = bytes.TrimSpace(valueRaw)
	}
	value, err := tronJSONUint(trimmed, bits)
	if err != nil {
		return "", err
	}
	return value.String(), nil
}

func validTronUnsignedDecimal(value string, bits int) bool {
	if len(value) == 0 || len(value) > 78 {
		return false
	}
	for _, digit := range value {
		if digit < '0' || digit > '9' {
			return false
		}
	}
	parsed, ok := new(big.Int).SetString(value, 10)
	return ok && parsed.Sign() >= 0 && parsed.BitLen() <= bits
}

func validTronText(value string, maxBytes int, allowEmpty bool) bool {
	if (!allowEmpty && value == "") || len(value) > maxBytes || !utf8.ValidString(value) {
		return false
	}
	for _, char := range value {
		if char < 0x20 || char == 0x7f {
			return false
		}
	}
	return true
}

func validTronAddress(value string) bool {
	if len(value) == 42 && strings.HasPrefix(strings.ToLower(value), "41") {
		decoded, err := hex.DecodeString(value)
		return err == nil && len(decoded) == 21
	}
	raw, ok := decodeTronBase58(value)
	if !ok || len(raw) != 25 || raw[0] != 0x41 {
		return false
	}
	first := sha256.Sum256(raw[:21])
	second := sha256.Sum256(first[:])
	return bytes.Equal(raw[21:], second[:4])
}

func decodeTronBase58(value string) ([]byte, bool) {
	const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
	if value == "" {
		return nil, false
	}
	n := new(big.Int)
	base := big.NewInt(58)
	for _, char := range value {
		index := strings.IndexRune(alphabet, char)
		if index < 0 {
			return nil, false
		}
		n.Mul(n, base)
		n.Add(n, big.NewInt(int64(index)))
	}
	decoded := n.Bytes()
	leading := 0
	for leading < len(value) && value[leading] == '1' {
		leading++
	}
	return append(make([]byte, leading), decoded...), true
}

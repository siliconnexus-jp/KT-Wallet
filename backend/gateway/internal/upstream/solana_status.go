package upstream

import (
	"bytes"
	"encoding/json"
	"errors"
	"reflect"
)

func decodeSolanaSignatureStatus(raw json.RawMessage) (string, error) {
	fields, err := decodeExactJSONObject(raw, "context", "value")
	if err != nil {
		return "", err
	}
	contextRaw, hasContext := fields["context"]
	valueRaw, hasValue := fields["value"]
	if !hasContext || !hasValue {
		return "", errors.New("incomplete Solana signature status result")
	}
	if err := decodeSolanaContext(contextRaw); err != nil {
		return "", err
	}
	contextFields, _ := decodeExactJSONObject(contextRaw, "slot", "apiVersion")
	contextSlot, err := parseSolanaU64(contextFields["slot"], false)
	if err != nil {
		return "", err
	}
	entries, err := decodeRawJSONArray(valueRaw, 1)
	if err != nil || len(entries) != 1 {
		return "", errors.New("signature status count does not match request")
	}
	entryRaw := bytes.TrimSpace(entries[0])
	if bytes.Equal(entryRaw, []byte("null")) {
		return "unknown", nil
	}
	entry, err := decodeExactJSONObject(
		entryRaw,
		"slot",
		"confirmations",
		"err",
		"status",
		"confirmationStatus",
	)
	if err != nil {
		return "", err
	}
	for _, required := range []string{"slot", "confirmations", "err", "status", "confirmationStatus"} {
		if _, exists := entry[required]; !exists {
			return "", errors.New("incomplete Solana signature status entry")
		}
	}
	transactionSlot, err := parseSolanaU64(entry["slot"], false)
	if err != nil || transactionSlot.Cmp(contextSlot) > 0 {
		return "", errors.New("invalid Solana transaction slot")
	}

	confirmationsNull := bytes.Equal(bytes.TrimSpace(entry["confirmations"]), []byte("null"))
	if !confirmationsNull {
		if _, err := parseSolanaU64(entry["confirmations"], false); err != nil {
			return "", errors.New("invalid Solana confirmations")
		}
	}

	confirmationStatus, confirmationKnown, err := decodeSolanaConfirmationStatus(entry["confirmationStatus"])
	if err != nil {
		return "", err
	}
	if confirmationKnown {
		if confirmationStatus == "finalized" && !confirmationsNull {
			return "", errors.New("finalized Solana status still has confirmations")
		}
		if confirmationStatus != "finalized" && confirmationsNull {
			return "", errors.New("unrooted Solana status has null confirmations")
		}
	}

	errRaw := bytes.TrimSpace(entry["err"])
	failed := !bytes.Equal(errRaw, []byte("null"))
	if failed && !validSolanaTransactionError(errRaw) {
		return "", errors.New("invalid Solana transaction error")
	}
	if err := validateSolanaDeprecatedStatus(entry["status"], errRaw, failed); err != nil {
		return "", err
	}
	if !confirmationKnown {
		return "unknown", nil
	}
	switch confirmationStatus {
	case "processed":
		return "pending", nil
	case "confirmed", "finalized":
		if failed {
			return "failed", nil
		}
		return "confirmed", nil
	default:
		return "", errors.New("unsupported Solana confirmation status")
	}
}

func decodeSolanaConfirmationStatus(raw json.RawMessage) (string, bool, error) {
	if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return "", false, nil
	}
	var status string
	if err := json.Unmarshal(raw, &status); err != nil {
		return "", false, errors.New("invalid Solana confirmation status")
	}
	switch status {
	case "processed", "confirmed", "finalized":
		return status, true, nil
	default:
		return "", false, errors.New("unknown Solana confirmation status")
	}
}

func validSolanaTransactionError(raw json.RawMessage) bool {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
		return false
	}
	if trimmed[0] == '"' {
		var name string
		return json.Unmarshal(trimmed, &name) == nil && name != "" && len(name) <= 128
	}
	if trimmed[0] != '{' {
		return false
	}
	fields, err := decodeUniqueJSONObject(trimmed)
	return err == nil && len(fields) == 1
}

func validateSolanaDeprecatedStatus(raw, errRaw json.RawMessage, failed bool) error {
	fields, err := decodeExactJSONObject(raw, "Ok", "Err")
	if err != nil || len(fields) != 1 {
		return errors.New("invalid deprecated Solana status")
	}
	if !failed {
		okRaw, exists := fields["Ok"]
		if !exists || !bytes.Equal(bytes.TrimSpace(okRaw), []byte("null")) {
			return errors.New("Solana success evidence conflicts with status")
		}
		return nil
	}
	statusErr, exists := fields["Err"]
	if !exists || !equivalentSolanaJSON(statusErr, errRaw) {
		return errors.New("Solana failure evidence conflicts with status")
	}
	return nil
}

func equivalentSolanaJSON(left, right json.RawMessage) bool {
	decode := func(raw json.RawMessage) (any, bool) {
		decoder := json.NewDecoder(bytes.NewReader(raw))
		decoder.UseNumber()
		var value any
		if err := decoder.Decode(&value); err != nil {
			return nil, false
		}
		if decoder.More() {
			return nil, false
		}
		return value, true
	}
	leftValue, leftOK := decode(left)
	rightValue, rightOK := decode(right)
	return leftOK && rightOK && reflect.DeepEqual(leftValue, rightValue)
}

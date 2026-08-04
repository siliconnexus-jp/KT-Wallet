package upstream

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

const (
	maxGoPlusMessageBytes   = 256
	maxGoPlusAuthorityRows  = 100
	maxGoPlusBehaviorRows   = 100
	maxGoPlusBehaviorLength = 96
)

var (
	goPlusChainIDPattern = regexp.MustCompile(`^[1-9][0-9]{0,19}$`)
	tronContractPattern  = regexp.MustCompile(`^T[1-9A-HJ-NP-Za-km-z]{33}$`)
	solanaMintPattern    = regexp.MustCompile(`^[1-9A-HJ-NP-Za-km-z]{32,44}$`)
)

type goPlusEnvelope struct {
	Code    int
	Message string
	Result  json.RawMessage
}

// decodeGoPlusEnvelope rejects duplicate, aliased and unknown envelope
// members. Message is informational and optional in older provider fixtures;
// when present it must still be a bounded JSON string. Code and result are
// security-relevant and always required.
func decodeGoPlusEnvelope(data []byte) (goPlusEnvelope, error) {
	fields, err := decodeExactJSONObject(data, "code", "message", "result")
	if err != nil {
		return goPlusEnvelope{}, err
	}
	codeRaw, hasCode := fields["code"]
	result, hasResult := fields["result"]
	if !hasCode || !hasResult {
		return goPlusEnvelope{}, errors.New("incomplete GoPlus envelope")
	}
	code, err := parseExactJSONInt(codeRaw, 0, 1_000_000)
	if err != nil {
		return goPlusEnvelope{}, errors.New("invalid GoPlus response code")
	}
	message := ""
	if raw, present := fields["message"]; present {
		if err := json.Unmarshal(raw, &message); err != nil || len(message) > maxGoPlusMessageBytes {
			return goPlusEnvelope{}, errors.New("invalid GoPlus response message")
		}
	}
	return goPlusEnvelope{Code: code, Message: message, Result: result}, nil
}

func parseExactJSONInt(raw json.RawMessage, minimum, maximum int64) (int, error) {
	value, err := parseExactJSONInt64(raw, minimum, maximum)
	return int(value), err
}

func parseExactJSONInt64(raw json.RawMessage, minimum, maximum int64) (int64, error) {
	text := strings.TrimSpace(string(raw))
	if text == "" || strings.IndexFunc(text, func(r rune) bool { return r < '0' || r > '9' }) >= 0 {
		return 0, errors.New("expected unsigned JSON integer")
	}
	value, err := strconv.ParseInt(text, 10, 64)
	if err != nil || value < minimum || value > maximum {
		return 0, errors.New("JSON integer out of range")
	}
	return value, nil
}

func isJSONNull(raw json.RawMessage) bool {
	return bytes.Equal(bytes.TrimSpace(raw), []byte("null"))
}

// decodeBoundGoPlusRecord accepts either an empty result (no record) or one
// record whose key is the requested public identity. Non-empty results with a
// different or additional key are request-unbound and fail closed.
func decodeBoundGoPlusRecord(
	raw json.RawMessage,
	identity string,
	caseInsensitive bool,
) (json.RawMessage, bool, error) {
	result, err := decodeUniqueJSONObject(raw)
	if err != nil {
		return nil, false, err
	}
	if len(result) == 0 {
		return nil, false, nil
	}
	if len(result) != 1 {
		return nil, false, errors.New("GoPlus result is not bound to one identity")
	}
	for key, record := range result {
		matches := key == identity
		if caseInsensitive {
			matches = strings.EqualFold(key, identity)
		}
		if !matches {
			return nil, false, errors.New("GoPlus result identity mismatch")
		}
		if len(bytes.TrimSpace(record)) == 0 || isJSONNull(record) {
			return nil, false, nil
		}
		return record, true, nil
	}
	panic("unreachable")
}

func rejectConsumedFieldAliases(fields map[string]json.RawMessage, consumed ...string) error {
	for key := range fields {
		for _, expected := range consumed {
			if key != expected && strings.EqualFold(key, expected) {
				return fmt.Errorf("ambiguous GoPlus member %q", key)
			}
		}
	}
	return nil
}

func requireJSONFields(fields map[string]json.RawMessage, required ...string) error {
	for _, key := range required {
		if _, present := fields[key]; !present {
			return fmt.Errorf("missing GoPlus member %q", key)
		}
	}
	return nil
}

func parseBinaryFlag(raw json.RawMessage) (bool, error) {
	text := strings.TrimSpace(string(raw))
	switch text {
	case "0", `"0"`:
		return false, nil
	case "1", `"1"`:
		return true, nil
	default:
		return false, errors.New("invalid GoPlus binary flag")
	}
}

func parseOptionalBinaryFlag(
	fields map[string]json.RawMessage,
	key string,
) (present bool, enabled bool, err error) {
	raw, present := fields[key]
	if !present {
		return false, false, nil
	}
	enabled, err = parseBinaryFlag(raw)
	return true, enabled, err
}

func decodeRawJSONArray(raw json.RawMessage, maximum int) ([]json.RawMessage, error) {
	var rows []json.RawMessage
	if err := json.Unmarshal(raw, &rows); err != nil || rows == nil || len(rows) > maximum {
		return nil, errors.New("invalid or oversized GoPlus array")
	}
	return rows, nil
}

func decodeBoundedString(raw json.RawMessage, maximum int, nullable bool) (string, error) {
	if nullable && isJSONNull(raw) {
		return "", nil
	}
	var value string
	if err := json.Unmarshal(raw, &value); err != nil || len(value) > maximum {
		return "", errors.New("invalid GoPlus string")
	}
	return value, nil
}

func decodeMaliciousBehaviors(raw json.RawMessage) ([]string, error) {
	rows, err := decodeRawJSONArray(raw, maxGoPlusBehaviorRows)
	if err != nil {
		return nil, err
	}
	behaviors := make([]string, 0, len(rows))
	seen := make(map[string]struct{}, len(rows))
	for _, row := range rows {
		value, err := decodeBoundedString(row, maxGoPlusBehaviorLength, false)
		value = strings.TrimSpace(value)
		if err != nil || value == "" {
			return nil, errors.New("invalid GoPlus malicious behavior")
		}
		if _, duplicate := seen[value]; duplicate {
			return nil, errors.New("duplicate GoPlus malicious behavior")
		}
		seen[value] = struct{}{}
		behaviors = append(behaviors, value)
	}
	return behaviors, nil
}

func validateGoPlusTokenIdentity(chainID, contract string) error {
	switch {
	case chainID == "tron":
		if !tronContractPattern.MatchString(contract) {
			return errors.New("invalid TRON token identity")
		}
	case goPlusChainIDPattern.MatchString(chainID):
		if !evmAddressPattern.MatchString(contract) {
			return errors.New("invalid EVM token identity")
		}
	default:
		return errors.New("invalid GoPlus chain identity")
	}
	return nil
}

func validateGoPlusApprovalIdentity(chainID, address string) error {
	if !goPlusChainIDPattern.MatchString(chainID) || !evmAddressPattern.MatchString(address) {
		return errors.New("invalid EVM approval identity")
	}
	return nil
}

func validateSolanaMint(mint string) error {
	if !solanaMintPattern.MatchString(mint) {
		return errors.New("invalid Solana mint")
	}
	return nil
}

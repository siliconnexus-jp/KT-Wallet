package upstream

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
)

// decodeExactJSONObject parses one JSON object while preserving each value as
// raw bytes. Unlike encoding/json's struct and map decoders, it rejects exact
// duplicate keys, case aliases and unknown members. It is used at provider
// trust boundaries where accepting two interpretations of the same response
// could change a balance, fee, transaction status or broadcast outcome.
func decodeExactJSONObject(raw []byte, allowedKeys ...string) (map[string]json.RawMessage, error) {
	values, err := decodeUniqueJSONObject(raw)
	if err != nil {
		return nil, err
	}
	allowed := make(map[string]struct{}, len(allowedKeys))
	for _, key := range allowedKeys {
		allowed[key] = struct{}{}
	}
	for key := range values {
		if _, known := allowed[key]; !known {
			return nil, fmt.Errorf("unknown JSON object key %q", key)
		}
	}
	return values, nil
}

// decodeUniqueJSONObject is used for provider objects whose complete field
// vocabulary is intentionally extensible (for example, an Ethereum block),
// while every key that KT Wallet consumes must still have one unambiguous
// spelling and value. It rejects duplicate keys but leaves the caller to
// validate its required exact members and case aliases.
func decodeUniqueJSONObject(raw []byte) (map[string]json.RawMessage, error) {
	if !json.Valid(raw) {
		return nil, errors.New("invalid JSON")
	}

	decoder := json.NewDecoder(bytes.NewReader(raw))
	first, err := decoder.Token()
	if err != nil {
		return nil, err
	}
	object, ok := first.(json.Delim)
	if !ok || object != '{' {
		return nil, errors.New("expected JSON object")
	}

	values := make(map[string]json.RawMessage)
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		key, ok := keyToken.(string)
		if !ok {
			return nil, errors.New("non-string JSON object key")
		}
		if _, duplicate := values[key]; duplicate {
			return nil, fmt.Errorf("duplicate JSON object key %q", key)
		}
		var value json.RawMessage
		if err := decoder.Decode(&value); err != nil {
			return nil, err
		}
		values[key] = value
	}
	end, err := decoder.Token()
	if err != nil {
		return nil, err
	}
	if end != json.Delim('}') {
		return nil, errors.New("unterminated JSON object")
	}
	return values, nil
}

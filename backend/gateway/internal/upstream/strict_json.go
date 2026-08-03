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
	if !json.Valid(raw) {
		return nil, errors.New("invalid JSON")
	}
	allowed := make(map[string]struct{}, len(allowedKeys))
	for _, key := range allowedKeys {
		allowed[key] = struct{}{}
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

	values := make(map[string]json.RawMessage, len(allowedKeys))
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		key, ok := keyToken.(string)
		if !ok {
			return nil, errors.New("non-string JSON object key")
		}
		if _, known := allowed[key]; !known {
			return nil, fmt.Errorf("unknown JSON object key %q", key)
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

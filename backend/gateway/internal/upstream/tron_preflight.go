package upstream

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
)

var ErrTronRateLimited = errors.New("TRON provider rate limited")

// FeeData uses the same server-only credential and redirect policy as balances.
// Paths and HTTP methods are fixed; constant calls only simulate, never submit.
func (t *Tron) FeeData(ctx context.Context, operation, address, contract, selector, parameter string) (json.RawMessage, error) {
	method, path := http.MethodPost, ""
	body := map[string]any{}
	switch operation {
	case "account":
		method, path = http.MethodGet, "/v1/accounts/"+address
	case "block":
		path = "/wallet/getnowblock"
	case "parameters":
		path = "/wallet/getchainparameters"
	case "resources":
		path = "/wallet/getaccountresource"
		body = map[string]any{"address": address, "visible": true}
	case "constant":
		path = "/wallet/triggerconstantcontract"
		body = map[string]any{"owner_address": address, "contract_address": contract,
			"function_selector": selector, "parameter": parameter, "visible": true}
	default:
		return nil, errors.New("unsupported TRON fee read")
	}
	encoded, _ := json.Marshal(body)
	if method == http.MethodGet {
		encoded = nil
	}
	data, err := t.fetch(ctx, method, path, encoded)
	if err != nil {
		return nil, err
	}
	var envelope map[string]json.RawMessage
	if err := json.Unmarshal(data, &envelope); err != nil || envelope == nil {
		return nil, t.unavailable("malformed TRON fee response")
	}
	// HTTP 200 can still be a provider error. Never interpret it as a zero
	// balance/resource allowance, and never return provider error text.
	if envelope["Error"] != nil || envelope["error"] != nil || string(envelope["success"]) == "false" {
		return nil, t.unavailable("TRON fee read failed")
	}
	return data, nil
}

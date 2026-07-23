package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"strings"

	"ktwallet/gateway/internal/rpc"
)

// Broadcast implements kt_broadcast. The payload is forwarded to the chain
// verbatim; nothing is ever cached. Malformed payloads are rejected before
// any upstream call.
func (g *Gateway) Broadcast(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Chain   string `json:"chain"`
		Network string `json:"network"`
		Payload string `json:"payload"`
	}
	if err := json.Unmarshal(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"chain", "network"?, "payload"}`)
	}
	meta, rpcErr := validateChain(p.Chain)
	if rpcErr != nil {
		return nil, rpcErr
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	if p.Payload == "" {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "payload" is required and must not be blank`)
	}

	var txHash string
	var err error
	switch {
	case meta.EVM:
		if !evmHexPayloadRe.MatchString(p.Payload) {
			return nil, rpc.Errorf(rpc.CodeInvalidParams,
				`invalid params: "payload" must be a 0x-prefixed even-length hex string for EVM chains`)
		}
		txHash, err = g.evm[network].SendRawTransaction(ctx, p.Payload)
	case p.Chain == "solana":
		if raw, decErr := base64.StdEncoding.DecodeString(p.Payload); decErr != nil || len(raw) == 0 {
			return nil, rpc.Errorf(rpc.CodeInvalidParams,
				`invalid params: "payload" must be a base64-encoded signed transaction for solana`)
		}
		txHash, err = g.sol[network].SendTransaction(ctx, p.Payload)
	default: // tron
		trimmed := strings.TrimSpace(p.Payload)
		if !strings.HasPrefix(trimmed, "{") || !json.Valid([]byte(trimmed)) {
			return nil, rpc.Errorf(rpc.CodeInvalidParams,
				`invalid params: "payload" must be a signed TronGrid transaction JSON object for tron`)
		}
		txHash, err = g.tron[network].Broadcast(ctx, []byte(trimmed))
	}
	if err != nil {
		upstreamName := p.Chain
		if p.Chain == "tron" {
			upstreamName = "trongrid"
		}
		return nil, upstreamError(upstreamName, err)
	}
	return map[string]string{"txHash": txHash}, nil
}

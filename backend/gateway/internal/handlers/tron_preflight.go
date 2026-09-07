package handlers

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

// GetTronFeeData exposes only the reads needed to prepare a TRON transfer.
// No caller-selected URLs, arbitrary contract methods, signing or broadcast.
// Account/resource/simulation data is deliberately not cached.
func (g *Gateway) GetTronFeeData(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Network   string `json:"network"`
		Operation string `json:"operation"`
		Address   string `json:"address"`
		Contract  string `json:"contract"`
		Selector  string `json:"selector"`
		Parameter string `json:"parameter"`
	}
	invalid := func() (any, *rpc.Error) {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, "invalid TRON fee read")
	}
	if err := decodeStrictJSON(params, &p); err != nil || len(params) == 0 {
		return invalid()
	}
	network, rpcErr := resolveNetwork("tron", p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	switch p.Operation {
	case "block", "parameters":
		if p.Address != "" {
			return invalid()
		}
	case "account", "resources", "constant":
		if validateAddress("tron", p.Address) != nil {
			return invalid()
		}
	default:
		return invalid()
	}
	if p.Operation == "constant" {
		if validateAddress("tron", p.Contract) != nil {
			return invalid()
		}
		length := 64
		if p.Selector == "transfer(address,uint256)" {
			length = 128
		} else if p.Selector != "balanceOf(address)" {
			return invalid()
		}
		if len(p.Parameter) != length {
			return invalid()
		}
		word, err := hex.DecodeString(p.Parameter)
		if err != nil {
			return invalid()
		}
		// ABI addresses must be canonical 20-byte words.
		for _, b := range word[:12] {
			if b != 0 {
				return invalid()
			}
		}
	} else if p.Contract != "" || p.Selector != "" || p.Parameter != "" {
		return invalid()
	}
	data, err := g.tron[network].FeeData(ctx, p.Operation, p.Address, p.Contract, p.Selector, p.Parameter)
	if errors.Is(err, upstream.ErrTronRateLimited) {
		return nil, rpc.Errorf(rpc.CodeRateLimited, "rate_limited")
	}
	if err != nil {
		return nil, upstreamError("tron", err)
	}
	return map[string]any{
		"network": network, "operation": p.Operation, "address": p.Address,
		"contract": p.Contract, "selector": p.Selector, "parameter": p.Parameter,
		"data": data,
	}, nil
}

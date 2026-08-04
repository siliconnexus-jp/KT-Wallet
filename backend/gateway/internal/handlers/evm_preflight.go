package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"math/big"
	"strings"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

const maxEVMCallDataBytes = 128 * 1024

type evmCallParams struct {
	Chain    string `json:"chain"`
	Network  string `json:"network"`
	From     string `json:"from"`
	To       string `json:"to"`
	Value    string `json:"value"`
	Data     string `json:"data"`
	BlockTag string `json:"blockTag"`
}

func (g *Gateway) validatedEVMCall(
	params json.RawMessage,
) (evmCallParams, string, *rpc.Error) {
	var p evmCallParams
	if err := decodeStrictJSON(params, &p); err != nil || len(params) == 0 {
		return p, "", rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: expected {"chain", "network"?, "from", "to", "value", "data"}`,
		)
	}
	meta, rpcErr := validateChain(p.Chain)
	if rpcErr != nil {
		return p, "", rpcErr
	}
	if !meta.EVM {
		return p, "", rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "chain" must be an EVM chain (%s)`,
			quotedList(evmChainOrder),
		)
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return p, "", rpcErr
	}
	if rpcErr := validateAddress(p.Chain, p.From); rpcErr != nil {
		return p, "", rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "from" must be a 0x-prefixed 20-byte hex address`,
		)
	}
	if rpcErr := validateAddress(p.Chain, p.To); rpcErr != nil {
		return p, "", rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "to" must be a 0x-prefixed 20-byte hex address`,
		)
	}
	value, ok := new(big.Int).SetString(p.Value, 10)
	if !ok || value.Sign() < 0 {
		return p, "", rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "value" must be a non-negative decimal integer`,
		)
	}
	if !validEVMData(p.Data) {
		return p, "", rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "data" must be 0x-prefixed even-length hex no larger than %d bytes`,
			maxEVMCallDataBytes,
		)
	}
	p.Value = "0x" + value.Text(16)
	p.Data = strings.ToLower(p.Data)
	if p.BlockTag != "" && p.BlockTag != "latest" && p.BlockTag != "pending" {
		return p, "", rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "blockTag" must be "latest" or "pending"`,
		)
	}
	return p, network, nil
}

// SimulateEVMTransfer implements kt_simulateEvmTransfer. This state-dependent
// answer is deliberately not cached.
func (g *Gateway) SimulateEVMTransfer(
	ctx context.Context,
	params json.RawMessage,
) (any, *rpc.Error) {
	p, network, rpcErr := g.validatedEVMCall(params)
	if rpcErr != nil {
		return nil, rpcErr
	}
	blockTag := p.BlockTag
	if blockTag == "" {
		blockTag = "pending"
	}
	returnData, err := g.evm[network].SimulateTransaction(
		ctx,
		p.From,
		p.To,
		p.Value,
		p.Data,
		blockTag,
	)
	if err != nil {
		return nil, upstreamError(p.Chain, err)
	}
	return map[string]string{
		"network":    network,
		"from":       p.From,
		"to":         p.To,
		"value":      p.Value,
		"data":       p.Data,
		"blockTag":   blockTag,
		"returnData": returnData,
	}, nil
}

// EstimateEVMGas implements kt_estimateEvmGas for the exact unsigned call.
// Like simulation, gas estimation is state-dependent and is never cached.
func (g *Gateway) EstimateEVMGas(
	ctx context.Context,
	params json.RawMessage,
) (any, *rpc.Error) {
	p, network, rpcErr := g.validatedEVMCall(params)
	if rpcErr != nil {
		return nil, rpcErr
	}
	gas, err := g.evm[network].EstimateGas(
		ctx,
		p.From,
		p.To,
		p.Value,
		p.Data,
	)
	if err != nil {
		return nil, upstreamError(p.Chain, err)
	}
	return map[string]string{
		"network": network,
		"from":    p.From,
		"to":      p.To,
		"value":   p.Value,
		"data":    p.Data,
		"gas":     gas.String(),
	}, nil
}

// GetEVMSpendableBalances implements kt_getEvmSpendableBalances. It reads the
// pending state and is deliberately uncached because these values authorize a
// transaction rather than merely decorating the portfolio UI.
func (g *Gateway) GetEVMSpendableBalances(
	ctx context.Context,
	params json.RawMessage,
) (any, *rpc.Error) {
	var p struct {
		Chain         string `json:"chain"`
		Network       string `json:"network"`
		Address       string `json:"address"`
		TokenContract string `json:"tokenContract"`
	}
	if err := decodeStrictJSON(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: expected {"chain", "network"?, "address", "tokenContract"?}`,
		)
	}
	meta, rpcErr := validateChain(p.Chain)
	if rpcErr != nil {
		return nil, rpcErr
	}
	if !meta.EVM {
		return nil, rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "chain" must be an EVM chain (%s)`,
			quotedList(evmChainOrder),
		)
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	if rpcErr := validateAddress(p.Chain, p.Address); rpcErr != nil {
		return nil, rpcErr
	}
	if p.TokenContract != "" {
		if rpcErr := validateAddress(p.Chain, p.TokenContract); rpcErr != nil {
			return nil, rpc.Errorf(
				rpc.CodeInvalidParams,
				`invalid params: "tokenContract" must be a 0x-prefixed 20-byte hex address`,
			)
		}
	}

	evm := g.evm[network]
	nativeLatest, err := evm.GetBalanceAt(ctx, p.Address, "latest")
	if err != nil {
		return nil, upstreamError(p.Chain, err)
	}
	pendingAvailable := true
	nativePending, err := evm.GetBalanceAt(ctx, p.Address, "pending")
	if err != nil {
		if !isPendingStateUnavailable(err) {
			return nil, upstreamError(p.Chain, err)
		}
		pendingAvailable = false
		nativePending = nativeLatest
	}
	result := map[string]any{
		"network": network,
		"address": p.Address,
		// Keep `native` during the rolling upgrade; new clients use the two
		// explicit state views to authorize replacement fee deltas safely.
		"native":           nativePending.String(),
		"nativePending":    nativePending.String(),
		"nativeLatest":     nativeLatest.String(),
		"pendingAvailable": pendingAvailable,
	}
	if p.TokenContract != "" {
		result["tokenContract"] = p.TokenContract
		blockTag := "pending"
		if !pendingAvailable {
			blockTag = "latest"
		}
		token, err := evm.TokenBalanceAt(ctx, p.TokenContract, p.Address, blockTag)
		if err != nil {
			if blockTag != "pending" || !isPendingStateUnavailable(err) {
				return nil, upstreamError(p.Chain, err)
			}
			pendingAvailable = false
			result["pendingAvailable"] = false
			token, err = evm.TokenBalanceAt(ctx, p.TokenContract, p.Address, "latest")
			if err != nil {
				return nil, upstreamError(p.Chain, err)
			}
		}
		result["token"] = token.String()
	}
	return result, nil
}

func isPendingStateUnavailable(err error) bool {
	var nodeErr *upstream.NodeError
	if !errors.As(err, &nodeErr) {
		return false
	}
	message := strings.ToLower(nodeErr.Message)
	return strings.Contains(message, "state not available for pending block") ||
		strings.Contains(message, "pending block is not available")
}

func validEVMData(data string) bool {
	if !strings.HasPrefix(data, "0x") || len(data)%2 != 0 {
		return false
	}
	if (len(data)-2)/2 > maxEVMCallDataBytes {
		return false
	}
	for _, c := range data[2:] {
		if !((c >= '0' && c <= '9') ||
			(c >= 'a' && c <= 'f') ||
			(c >= 'A' && c <= 'F')) {
			return false
		}
	}
	return true
}

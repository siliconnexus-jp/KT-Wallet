package handlers

import (
	"context"
	"encoding/json"
	"math/big"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

type feeTier struct {
	MaxPriorityFeePerGas string `json:"maxPriorityFeePerGas"`
	MaxFeePerGas         string `json:"maxFeePerGas"`
}

type chainParamsResult struct {
	Nonce string `json:"nonce"`
	Fees  struct {
		Slow     feeTier `json:"slow"`
		Standard feeTier `json:"standard"`
		Fast     feeTier `json:"fast"`
	} `json:"fees"`
}

// feePercentiles are the eth_feeHistory reward percentiles backing the
// slow/standard/fast tiers.
var feePercentiles = []float64{10, 50, 90}

const feeHistoryBlocks = 5

// GetChainParams implements kt_getChainParams (EVM chains only).
func (g *Gateway) GetChainParams(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Chain   string `json:"chain"`
		Network string `json:"network"`
		Address string `json:"address"`
	}
	if err := json.Unmarshal(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"chain", "network"?, "address"}`)
	}
	meta, rpcErr := validateChain(p.Chain)
	if rpcErr != nil {
		return nil, rpcErr
	}
	if !meta.EVM {
		return nil, rpc.Errorf(rpc.CodeInvalidParams,
			`invalid params: "chain" must be an EVM chain (%s) for kt_getChainParams`, quotedList(evmChainOrder))
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	if rpcErr := validateAddress(p.Chain, p.Address); rpcErr != nil {
		return nil, rpcErr
	}

	key := network + "|" + p.Address
	if v, ok := g.paramsCache.Get(key); ok {
		return v, nil
	}

	evm := g.evm[network]
	nonce, err := evm.TransactionCount(ctx, p.Address)
	if err != nil {
		return nil, upstreamError(p.Chain, err)
	}

	res := &chainParamsResult{Nonce: nonce.String()}
	tiers, tierErr := g.feeTiersFromHistory(ctx, evm)
	if tierErr != nil {
		// eth_feeHistory unavailable or unusable on this node: fall back to
		// eth_gasPrice-derived tiers.
		tiers, err = g.feeTiersFromGasPrice(ctx, evm)
		if err != nil {
			return nil, upstreamError(p.Chain, err)
		}
	}
	res.Fees.Slow, res.Fees.Standard, res.Fees.Fast = tiers[0], tiers[1], tiers[2]

	g.paramsCache.Set(key, res)
	return res, nil
}

// feeTiersFromHistory derives tiers from eth_feeHistory: the priority fee per
// tier is the average of that percentile across the sampled blocks, and
// maxFee = 2*nextBaseFee + priority. Percentile ordering makes the tiers
// monotonic by construction.
func (g *Gateway) feeTiersFromHistory(ctx context.Context, evm *upstream.EVM) ([3]feeTier, error) {
	var tiers [3]feeTier
	fh, err := evm.FeeHistory(ctx, feeHistoryBlocks, feePercentiles)
	if err != nil {
		return tiers, err
	}
	if len(fh.BaseFeePerGas) == 0 || len(fh.Reward) == 0 {
		return tiers, &upstream.Unavailable{Upstream: "evm", Message: "empty eth_feeHistory result"}
	}
	baseFee := fh.BaseFeePerGas[len(fh.BaseFeePerGas)-1]

	sums := [3]*big.Int{big.NewInt(0), big.NewInt(0), big.NewInt(0)}
	blocks := 0
	for _, row := range fh.Reward {
		if len(row) < len(feePercentiles) {
			continue
		}
		for i := range sums {
			sums[i].Add(sums[i], row[i])
		}
		blocks++
	}
	if blocks == 0 {
		return tiers, &upstream.Unavailable{Upstream: "evm", Message: "eth_feeHistory returned no usable reward rows"}
	}
	n := big.NewInt(int64(blocks))
	for i := range tiers {
		prio := new(big.Int).Div(sums[i], n)
		maxFee := new(big.Int).Mul(baseFee, big.NewInt(2))
		maxFee.Add(maxFee, prio)
		tiers[i] = feeTier{MaxPriorityFeePerGas: prio.String(), MaxFeePerGas: maxFee.String()}
	}
	return tiers, nil
}

// feeTiersFromGasPrice derives tiers from a single eth_gasPrice sample using
// fixed monotonic multipliers.
func (g *Gateway) feeTiersFromGasPrice(ctx context.Context, evm *upstream.EVM) ([3]feeTier, error) {
	var tiers [3]feeTier
	gp, err := evm.GasPrice(ctx)
	if err != nil {
		return tiers, err
	}
	pct := func(mul int64) *big.Int {
		v := new(big.Int).Mul(gp, big.NewInt(mul))
		return v.Div(v, big.NewInt(100))
	}
	tiers[0] = feeTier{MaxPriorityFeePerGas: pct(10).String(), MaxFeePerGas: pct(100).String()}
	tiers[1] = feeTier{MaxPriorityFeePerGas: pct(15).String(), MaxFeePerGas: pct(125).String()}
	tiers[2] = feeTier{MaxPriorityFeePerGas: pct(20).String(), MaxFeePerGas: pct(150).String()}
	return tiers, nil
}

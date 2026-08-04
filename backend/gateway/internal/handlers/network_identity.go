package handlers

import (
	"context"
	"encoding/json"
	"fmt"

	"ktwallet/gateway/internal/rpc"
)

// GetNetworkIdentity implements kt_getNetworkIdentity. It asks the live
// upstream for the EVM chain id, TRON block-zero id or Solana genesis hash,
// then compares that value with the reviewed network registry before exposing
// it to a signing client. A misrouted Gateway therefore fails closed.
func (g *Gateway) GetNetworkIdentity(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Chain   string `json:"chain"`
		Network string `json:"network"`
	}
	if err := decodeStrictJSON(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"chain", "network"?}`)
	}
	meta, rpcErr := validateChain(p.Chain)
	if rpcErr != nil {
		return nil, rpcErr
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}

	var identity string
	var err error
	switch {
	case meta.EVM:
		identity, err = g.evm[network].ChainID(ctx)
	case p.Chain == "tron":
		identity, err = g.tron[network].GenesisBlockID(ctx)
	default:
		identity, err = g.sol[network].GenesisHash(ctx)
	}
	if err != nil {
		return nil, upstreamError("network_identity", err)
	}
	if identity != networks[network].Identity {
		return nil, upstreamError("network_identity", fmt.Errorf("live network identity mismatch"))
	}
	return map[string]string{"network": network, "identity": identity}, nil
}

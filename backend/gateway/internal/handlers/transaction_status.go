package handlers

import (
	"context"
	"encoding/json"
	"regexp"
	"strings"

	"ktwallet/gateway/internal/rpc"
)

var evmTxHashRe = regexp.MustCompile(`^0x[0-9a-fA-F]{64}$`)
var tronTxHashRe = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)

// GetTransactionStatus implements kt_getTransactionStatus. It queries the
// chain RPC by hash/signature and therefore becomes authoritative before an
// account-history indexer has caught up.
func (g *Gateway) GetTransactionStatus(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Chain   string `json:"chain"`
		Network string `json:"network"`
		Hash    string `json:"hash"`
	}
	if err := decodeStrictJSON(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"chain", "network"?, "hash"}`)
	}
	meta, rpcErr := validateChain(p.Chain)
	if rpcErr != nil {
		return nil, rpcErr
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	p.Hash = strings.TrimSpace(p.Hash)
	switch {
	case meta.EVM && !evmTxHashRe.MatchString(p.Hash):
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "hash" must be a 0x-prefixed 32-byte transaction hash`)
	case p.Chain == "tron" && !tronTxHashRe.MatchString(p.Hash):
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "hash" must be a 32-byte hex transaction id`)
	case p.Chain == "solana" && !isValidSolanaSignature(p.Hash):
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "hash" must be a Solana transaction signature`)
	}

	var status string
	var err error
	switch {
	case meta.EVM:
		status, err = g.evm[network].TransactionStatus(ctx, p.Hash)
	case p.Chain == "tron":
		status, err = g.tron[network].TransactionStatus(ctx, p.Hash)
	default:
		status, err = g.sol[network].SignatureStatus(ctx, p.Hash)
	}
	if err != nil {
		return nil, upstreamError("transaction_status", err)
	}
	return map[string]string{"status": status}, nil
}

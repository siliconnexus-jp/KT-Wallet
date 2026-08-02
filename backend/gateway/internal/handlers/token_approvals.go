package handlers

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"sync/atomic"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

// GoPlus Approval Management v2 currently documents these KT Wallet
// mainnets. Testnets and Avalanche are deliberately unsupported rather than
// being reported as an empty/safe approval list.
var goPlusApprovalChainIDs = map[string]string{
	"eth-mainnet":      "1",
	"polygon-mainnet":  "137",
	"base-mainnet":     "8453",
	"arbitrum-mainnet": "42161",
	"bnb-mainnet":      "56",
}

type tokenApprovalProviderMetrics struct {
	lookups   atomic.Uint64
	errors    atomic.Uint64
	cacheHits atomic.Uint64
	rows      atomic.Uint64
	riskyRows atomic.Uint64
}

// GetEVMTokenApprovals returns outstanding ERC-20 allowances for one public
// EOA. The request is privacy-sensitive: unlike a token contract lookup, it
// sends the wallet's public address to an external provider. The caller must
// therefore set privacyConsent=true after a user-facing disclosure.
//
// A provider failure is an upstream error, never an empty list. Unsupported
// networks return -32002, never an apparently clean result.
func (g *Gateway) GetEVMTokenApprovals(
	ctx context.Context,
	params json.RawMessage,
) (any, *rpc.Error) {
	var p struct {
		Chain          string `json:"chain"`
		Network        string `json:"network"`
		Address        string `json:"address"`
		PrivacyConsent bool   `json:"privacyConsent"`
	}
	if err := json.Unmarshal(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: expected {"chain", "network"?, "address", "privacyConsent":true}`,
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
		return nil, rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "address" must be a 0x-prefixed 20-byte hex address`,
		)
	}
	if !p.PrivacyConsent {
		return nil, rpc.Errorf(
			rpc.CodeInvalidParams,
			`invalid params: "privacyConsent" must be true`,
		)
	}
	chainID, supported := goPlusApprovalChainIDs[network]
	if !supported || g.goPlusApprovals == nil {
		return nil, rpc.Errorf(
			rpc.CodeUnsupported,
			"token approvals are unsupported for %s",
			network,
		)
	}

	cacheKey := approvalCacheKey(network, p.Address)
	if cached, ok := g.tokenApprovalsCache.Get(cacheKey); ok {
		if rows, ok := cached.([]upstream.TokenApproval); ok {
			g.tokenApprovalMetrics.cacheHits.Add(1)
			return tokenApprovalsResult(network, rows), nil
		}
	}
	permit, allowed := g.goPlusApprovalsCircuit.allow()
	if !allowed {
		return nil, upstreamError("goplus-approvals", &upstream.Unavailable{
			Upstream: "goplus-approvals",
			Message:  "provider circuit open",
		})
	}
	g.tokenApprovalMetrics.lookups.Add(1)
	rows, err := g.goPlusApprovals.TokenApprovals(ctx, chainID, p.Address)
	g.goPlusApprovalsCircuit.finish(permit, err == nil, ctx.Err() == nil)
	if err != nil {
		g.tokenApprovalMetrics.errors.Add(1)
		return nil, upstreamError("goplus-approvals", err)
	}
	// Cache only the provider's sanitized approval rows under a one-way key;
	// the owner address itself is not retained in the cache value or key.
	g.tokenApprovalsCache.Set(cacheKey, rows)
	g.tokenApprovalMetrics.rows.Add(uint64(len(rows)))
	for _, row := range rows {
		if row.TokenRisky || row.SpenderRisky {
			g.tokenApprovalMetrics.riskyRows.Add(1)
		}
	}
	return tokenApprovalsResult(network, rows), nil
}

func approvalCacheKey(network, address string) string {
	digest := sha256.Sum256([]byte(network + "|" + strings.ToLower(address)))
	return hex.EncodeToString(digest[:])
}

func tokenApprovalsResult(network string, rows []upstream.TokenApproval) map[string]any {
	items := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		risk := "unknown"
		if row.TokenRisky || row.SpenderRisky {
			risk = "unsafe"
		}
		items = append(items, map[string]any{
			"tokenAddress":   row.TokenAddress,
			"tokenName":      row.TokenName,
			"tokenSymbol":    row.TokenSymbol,
			"decimals":       row.Decimals,
			"balance":        row.Balance,
			"spender":        row.Spender,
			"spenderName":    row.SpenderName,
			"spenderTag":     row.SpenderTag,
			"spenderTrusted": row.SpenderTrusted,
			"amount":         row.Amount,
			"unlimited":      row.Unlimited,
			"approvedAt":     row.ApprovedAt,
			"transaction":    row.Transaction,
			"risk":           risk,
		})
	}
	return map[string]any{
		"status":    "ok",
		"source":    "goplus",
		"network":   network,
		"approvals": items,
	}
}

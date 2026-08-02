package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync/atomic"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

var goPlusChainIDs = map[string]string{
	"eth-mainnet":       "1",
	"polygon-mainnet":   "137",
	"base-mainnet":      "8453",
	"arbitrum-mainnet":  "42161",
	"avalanche-mainnet": "43114",
	"bnb-mainnet":       "56",
	"tron-mainnet":      "tron",
}

type tokenRiskProviderMetrics struct {
	lookups   atomic.Uint64
	unsafe    atomic.Uint64
	unknown   atomic.Uint64
	errors    atomic.Uint64
	cacheHits atomic.Uint64
}

// TokenRisk is one exact network + contract/mint identity classified by the
// KT Wallet operator. Symbols and names are intentionally absent: neither is
// a cryptographic identity and both are routinely copied by scam tokens.
type TokenRisk struct {
	Network  string `json:"network"`
	Contract string `json:"contract"`
	Category string `json:"category"`
}

var allowedTokenRiskCategories = map[string]bool{
	"malicious":     true,
	"phishing":      true,
	"spam":          true,
	"impersonation": true,
	"honeypot":      true,
	"suspicious":    true,
}

// LoadTokenRisksFile reads the operator-managed risk registry. A malformed,
// unsupported or duplicate row rejects the entire file: partial protection is
// dangerous because it looks operational while silently losing entries.
func LoadTokenRisksFile(path string) ([]TokenRisk, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var entries []TokenRisk
	if err := json.Unmarshal(raw, &entries); err != nil {
		return nil, fmt.Errorf("decode token risks: %w", err)
	}
	index, err := normalizeTokenRisks(entries)
	if err != nil {
		return nil, err
	}
	out := make([]TokenRisk, 0, len(index))
	for _, entry := range entries {
		normalized, err := normalizeTokenRisk(entry)
		if err != nil {
			return nil, err
		}
		out = append(out, normalized)
	}
	return out, nil
}

func normalizeTokenRisks(entries []TokenRisk) (map[string]TokenRisk, error) {
	if entries == nil {
		return nil, errors.New("token risk registry must be a JSON array")
	}
	out := make(map[string]TokenRisk, len(entries))
	for i, entry := range entries {
		normalized, err := normalizeTokenRisk(entry)
		if err != nil {
			return nil, fmt.Errorf("risk %d: %w", i, err)
		}
		key := tokenIdentityKey(normalized.Network, normalized.Contract)
		if _, exists := out[key]; exists {
			return nil, fmt.Errorf("risk %d: duplicate network and contract", i)
		}
		out[key] = normalized
	}
	return out, nil
}

func normalizeTokenRisk(entry TokenRisk) (TokenRisk, error) {
	entry.Network = strings.TrimSpace(entry.Network)
	entry.Contract = strings.TrimSpace(entry.Contract)
	entry.Category = strings.ToLower(strings.TrimSpace(entry.Category))
	meta, ok := networks[entry.Network]
	if !ok {
		return TokenRisk{}, fmt.Errorf("unsupported network %q", entry.Network)
	}
	if err := validateAddress(meta.Chain, entry.Contract); err != nil {
		return TokenRisk{}, errors.New("invalid contract or mint")
	}
	switch meta.Chain {
	case "tron":
		if len(entry.Contract) != 34 ||
			!strings.HasPrefix(entry.Contract, "T") ||
			!base58TokenAddressRe.MatchString(entry.Contract) {
			return TokenRisk{}, errors.New("invalid TRON contract")
		}
	case "solana":
		if len(entry.Contract) < 32 ||
			len(entry.Contract) > 44 ||
			!base58TokenAddressRe.MatchString(entry.Contract) {
			return TokenRisk{}, errors.New("invalid Solana mint")
		}
	}
	if chains[meta.Chain].EVM {
		entry.Contract = strings.ToLower(entry.Contract)
	}
	if !allowedTokenRiskCategories[entry.Category] {
		return TokenRisk{}, fmt.Errorf("unsupported category %q", entry.Category)
	}
	return entry, nil
}

func tokenIdentityKey(network, contract string) string {
	if meta, ok := networks[network]; ok && chains[meta.Chain].EVM {
		contract = strings.ToLower(contract)
	}
	return network + "|" + contract
}

// CheckTokenRisk returns a deliberately small three-state contract:
//
//   - unsafe: exact match in the operator risk registry;
//   - safe: exact match in the operator verified-token catalog;
//   - unknown: neither source can establish an identity or the independent
//     provider found no explicit high-confidence malicious evidence.
//
// Registry matches take precedence so an operator can immediately revoke a
// previously verified identity. The external provider is consulted for its
// supported mainnet identities, including official tokens, so explicit threat
// evidence can override a blue identity badge. Provider failure becomes an RPC
// error so the mobile client renders "unable to check", never a green state.
func (g *Gateway) CheckTokenRisk(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Chain    string `json:"chain"`
		Network  string `json:"network"`
		Contract string `json:"contract"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, rpc.Errorf(rpc.CodeInvalidParams,
			`invalid params: expected {"chain", "network"?, "contract"}`)
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	entry, err := normalizeTokenRisk(TokenRisk{
		Network: network, Contract: p.Contract, Category: "suspicious",
	})
	if err != nil {
		return nil, rpc.Errorf(rpc.CodeInvalidParams,
			`invalid params: "contract" is not valid for %s`, network)
	}
	key := tokenIdentityKey(network, entry.Contract)
	if risk, found := g.tokenRisks[key]; found {
		return map[string]any{
			"status":   "unsafe",
			"category": risk.Category,
			"source":   "operator_registry",
		}, nil
	}
	_, official := g.officialByNetwork[network][entry.Contract]
	chainID, supported := goPlusChainIDs[network]
	if g.goPlusSolana != nil && network == "sol-mainnet" {
		return g.lookupExternalTokenRisk(
			ctx,
			network,
			entry.Contract,
			official,
			"goplus-solana",
			g.goPlusSolanaCircuit,
			func(ctx context.Context) (upstream.TokenThreat, error) {
				return g.goPlusSolana.TokenRisk(ctx, entry.Contract)
			},
		)
	}
	if g.goPlus != nil && supported {
		return g.lookupExternalTokenRisk(
			ctx,
			network,
			entry.Contract,
			official,
			"goplus",
			g.goPlusCircuit,
			func(ctx context.Context) (upstream.TokenThreat, error) {
				return g.goPlus.TokenRisk(ctx, chainID, entry.Contract)
			},
		)
	}
	if official {
		return map[string]any{
			"status": "safe",
			"source": "official_catalog",
		}, nil
	}
	return map[string]any{
		"status": "unknown",
		"source": "operator_registry",
	}, nil
}

func (g *Gateway) lookupExternalTokenRisk(
	ctx context.Context,
	network string,
	contract string,
	official bool,
	providerName string,
	circuit *providerCircuit,
	lookup func(context.Context) (upstream.TokenThreat, error),
) (any, *rpc.Error) {
	key := tokenIdentityKey(network, contract)
	if cached, ok := g.tokenRiskCache.Get(key); ok {
		if threat, ok := cached.(upstream.TokenThreat); ok {
			g.tokenRiskMetrics.cacheHits.Add(1)
			return externalTokenRiskResult(threat, official), nil
		}
	}
	permit, allowed := circuit.allow()
	if !allowed {
		return nil, upstreamError(providerName, &upstream.Unavailable{
			Upstream: providerName,
			Message:  "provider circuit open",
		})
	}
	g.tokenRiskMetrics.lookups.Add(1)
	threat, err := lookup(ctx)
	circuit.finish(permit, err == nil, ctx.Err() == nil)
	if err != nil {
		g.tokenRiskMetrics.errors.Add(1)
		return nil, upstreamError(providerName, err)
	}
	g.tokenRiskCache.Set(key, threat)
	if threat.Unsafe {
		g.tokenRiskMetrics.unsafe.Add(1)
	} else {
		g.tokenRiskMetrics.unknown.Add(1)
	}
	return externalTokenRiskResult(threat, official), nil
}

func externalTokenRiskResult(threat upstream.TokenThreat, official bool) map[string]any {
	if threat.Unsafe {
		return map[string]any{
			"status":   "unsafe",
			"category": threat.Category,
			"source":   "goplus",
		}
	}
	if official {
		return map[string]any{
			"status": "safe",
			"source": "official_catalog+goplus",
		}
	}
	return map[string]any{
		"status": "unknown",
		"source": "goplus",
	}
}

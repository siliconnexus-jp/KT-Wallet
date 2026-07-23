package handlers

import "ktwallet/gateway/internal/rpc"

// networkMeta describes one supported network id. Every network belongs to
// exactly one chain family ("eth", "polygon", "tron", "solana"); the family's
// mainnet is what an omitted "network" param resolves to.
type networkMeta struct {
	Chain            string // owning chain family
	Mainnet          bool   // the family's default network
	EtherscanChainID int    // Etherscan v2 chainid (EVM networks only)
}

// networkOrder is the canonical listing order (kt_health, error messages).
var networkOrder = []string{
	"eth-mainnet", "eth-sepolia",
	"polygon-mainnet", "polygon-amoy",
	"tron-mainnet", "tron-nile",
	"sol-mainnet", "sol-devnet",
}

var networks = map[string]networkMeta{
	"eth-mainnet":     {Chain: "eth", Mainnet: true, EtherscanChainID: 1},
	"eth-sepolia":     {Chain: "eth", EtherscanChainID: 11155111},
	"polygon-mainnet": {Chain: "polygon", Mainnet: true, EtherscanChainID: 137},
	"polygon-amoy":    {Chain: "polygon", EtherscanChainID: 80002},
	"tron-mainnet":    {Chain: "tron", Mainnet: true},
	"tron-nile":       {Chain: "tron"},
	"sol-mainnet":     {Chain: "solana", Mainnet: true},
	"sol-devnet":      {Chain: "solana"},
}

// mainnetOf maps a chain family to its default network id.
var mainnetOf = func() map[string]string {
	m := make(map[string]string, len(networks))
	for id, meta := range networks {
		if meta.Mainnet {
			m[meta.Chain] = id
		}
	}
	return m
}()

// resolveNetwork turns the optional "network" param into a concrete network
// id. An empty network selects the chain's mainnet (the pre-network behavior);
// an unknown id or a network belonging to a different chain family is a
// -32602 naming the offending field. chain must already be validated.
func resolveNetwork(chain, network string) (string, *rpc.Error) {
	if network == "" {
		return mainnetOf[chain], nil
	}
	meta, ok := networks[network]
	if !ok {
		return "", rpc.Errorf(rpc.CodeInvalidParams,
			`invalid params: "network" must be one of "eth-mainnet", "eth-sepolia", "polygon-mainnet", "polygon-amoy", "tron-mainnet", "tron-nile", "sol-mainnet", "sol-devnet"`)
	}
	if meta.Chain != chain {
		return "", rpc.Errorf(rpc.CodeInvalidParams,
			`invalid params: "network" %q does not belong to chain %q (it is a %q network)`, network, chain, meta.Chain)
	}
	return network, nil
}

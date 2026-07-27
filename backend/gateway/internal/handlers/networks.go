package handlers

import "ktwallet/gateway/internal/rpc"

// networkMeta describes one supported network id. Every network belongs to
// exactly one chain family (see chainOrder in validate.go); the family's
// mainnet is what an omitted "network" param resolves to.
type networkMeta struct {
	Chain            string // owning chain family
	Mainnet          bool   // the family's default network
	EtherscanChainID int    // Etherscan v2 chainid (EVM networks only)
}

// networkOrder is the canonical listing order (kt_health, error messages).
// The ids are exactly the app's built-in Network.id values, so the client can
// send NetworkController.activeFor(chain).id verbatim.
var networkOrder = []string{
	"eth-mainnet", "eth-sepolia",
	"polygon-mainnet", "polygon-amoy",
	"base-mainnet", "base-sepolia",
	"arbitrum-mainnet", "arbitrum-sepolia",
	"avalanche-mainnet", "avalanche-fuji",
	"tron-mainnet", "tron-nile",
	"sol-mainnet", "sol-devnet",
}

var networks = map[string]networkMeta{
	"eth-mainnet":       {Chain: "eth", Mainnet: true, EtherscanChainID: 1},
	"eth-sepolia":       {Chain: "eth", EtherscanChainID: 11155111},
	"polygon-mainnet":   {Chain: "polygon", Mainnet: true, EtherscanChainID: 137},
	"polygon-amoy":      {Chain: "polygon", EtherscanChainID: 80002},
	"base-mainnet":      {Chain: "base", Mainnet: true, EtherscanChainID: 8453},
	"base-sepolia":      {Chain: "base", EtherscanChainID: 84532},
	"arbitrum-mainnet":  {Chain: "arbitrum", Mainnet: true, EtherscanChainID: 42161},
	"arbitrum-sepolia":  {Chain: "arbitrum", EtherscanChainID: 421614},
	"avalanche-mainnet": {Chain: "avalanche", Mainnet: true, EtherscanChainID: 43114},
	"avalanche-fuji":    {Chain: "avalanche", EtherscanChainID: 43113},
	"tron-mainnet":      {Chain: "tron", Mainnet: true},
	"tron-nile":         {Chain: "tron"},
	"sol-mainnet":       {Chain: "solana", Mainnet: true},
	"sol-devnet":        {Chain: "solana"},
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
			`invalid params: "network" must be one of %s`, quotedList(networkOrder))
	}
	if meta.Chain != chain {
		return "", rpc.Errorf(rpc.CodeInvalidParams,
			`invalid params: "network" %q does not belong to chain %q (it is a %q network)`, network, chain, meta.Chain)
	}
	return network, nil
}

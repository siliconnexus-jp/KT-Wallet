package handlers

import "ktwallet/gateway/internal/rpc"

// networkMeta describes one supported network id. Every network belongs to
// exactly one chain family (see chainOrder in validate.go); the family's
// mainnet is what an omitted "network" param resolves to.
type networkMeta struct {
	Chain            string // owning chain family
	Mainnet          bool   // the family's default network
	EtherscanChainID int    // Etherscan v2 chainid (EVM networks only)
	Identity         string // decimal chain id, genesis block id or genesis hash
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
	"bnb-mainnet", "bnb-testnet",
	"tron-mainnet", "tron-nile",
	"sol-mainnet", "sol-devnet",
}

var networks = map[string]networkMeta{
	"eth-mainnet":       {Chain: "eth", Mainnet: true, EtherscanChainID: 1, Identity: "1"},
	"eth-sepolia":       {Chain: "eth", EtherscanChainID: 11155111, Identity: "11155111"},
	"polygon-mainnet":   {Chain: "polygon", Mainnet: true, EtherscanChainID: 137, Identity: "137"},
	"polygon-amoy":      {Chain: "polygon", EtherscanChainID: 80002, Identity: "80002"},
	"base-mainnet":      {Chain: "base", Mainnet: true, EtherscanChainID: 8453, Identity: "8453"},
	"base-sepolia":      {Chain: "base", EtherscanChainID: 84532, Identity: "84532"},
	"arbitrum-mainnet":  {Chain: "arbitrum", Mainnet: true, EtherscanChainID: 42161, Identity: "42161"},
	"arbitrum-sepolia":  {Chain: "arbitrum", EtherscanChainID: 421614, Identity: "421614"},
	"avalanche-mainnet": {Chain: "avalanche", Mainnet: true, EtherscanChainID: 43114, Identity: "43114"},
	"avalanche-fuji":    {Chain: "avalanche", EtherscanChainID: 43113, Identity: "43113"},
	"bnb-mainnet":       {Chain: "bnb", Mainnet: true, EtherscanChainID: 56, Identity: "56"},
	"bnb-testnet":       {Chain: "bnb", EtherscanChainID: 97, Identity: "97"},
	"tron-mainnet": {Chain: "tron", Mainnet: true,
		Identity: "00000000000000001ebf88508a03865c71d452e25f4d51194196a1d22b6653dc"},
	"tron-nile": {Chain: "tron",
		Identity: "0000000000000000d698d4192c56cb6be724a558448e2684802de4d6cd8690dc"},
	"sol-mainnet": {Chain: "solana", Mainnet: true,
		Identity: "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"},
	"sol-devnet": {Chain: "solana",
		Identity: "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG"},
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

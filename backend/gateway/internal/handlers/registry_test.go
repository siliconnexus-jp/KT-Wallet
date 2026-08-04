package handlers

import "testing"

// Registry invariants. Adding a network without wiring its upstream pool would
// otherwise surface as a nil-map dereference on the first request for it.
func TestEveryNetworkHasAnUpstreamPool(t *testing.T) {
	g := New(Config{})
	for id, meta := range networks {
		if meta.Identity == "" {
			t.Errorf("network %q has no pinned live identity", id)
		}
		chain, ok := chains[meta.Chain]
		if !ok {
			t.Fatalf("network %q belongs to unknown chain family %q", id, meta.Chain)
		}
		switch {
		case chain.EVM:
			if g.evm[id] == nil {
				t.Errorf("EVM network %q has no upstream pool", id)
			}
			if meta.EtherscanChainID == 0 {
				t.Errorf("EVM network %q has no Etherscan v2 chainid (history would query chainid=0)", id)
			}
		case meta.Chain == "tron":
			if g.tron[id] == nil {
				t.Errorf("tron network %q has no TronGrid client", id)
			}
		case meta.Chain == "solana":
			if g.sol[id] == nil {
				t.Errorf("solana network %q has no RPC client", id)
			}
			if g.hel[id] == nil {
				t.Errorf("solana network %q has no Helius client", id)
			}
		}
	}
}

func TestEveryChainFamilyHasExactlyOneMainnet(t *testing.T) {
	seen := map[string]string{}
	for id, meta := range networks {
		if !meta.Mainnet {
			continue
		}
		if prev, dup := seen[meta.Chain]; dup {
			t.Fatalf("chain %q has two mainnets: %q and %q", meta.Chain, prev, id)
		}
		seen[meta.Chain] = id
	}
	for _, chain := range chainOrder {
		if seen[chain] == "" {
			t.Errorf("chain %q has no mainnet network (an omitted \"network\" param would resolve to \"\")", chain)
		}
		if mainnetOf[chain] != seen[chain] {
			t.Errorf("mainnetOf[%q] = %q, want %q", chain, mainnetOf[chain], seen[chain])
		}
	}
}

// networkOrder drives kt_health and the -32602 message; a network missing from
// it would be accepted but undiscoverable.
func TestNetworkOrderCoversTheRegistry(t *testing.T) {
	if len(networkOrder) != len(networks) {
		t.Fatalf("networkOrder has %d ids, registry has %d", len(networkOrder), len(networks))
	}
	for _, id := range networkOrder {
		if _, ok := networks[id]; !ok {
			t.Errorf("networkOrder lists unknown network %q", id)
		}
	}
}

func TestChainOrderCoversTheRegistry(t *testing.T) {
	if len(chainOrder) != len(chains) {
		t.Fatalf("chainOrder has %d families, registry has %d", len(chainOrder), len(chains))
	}
	for _, chain := range chainOrder {
		if _, ok := chains[chain]; !ok {
			t.Errorf("chainOrder lists unknown chain %q", chain)
		}
	}
}

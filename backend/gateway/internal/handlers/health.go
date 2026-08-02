package handlers

import (
	"context"
	"encoding/json"
	"sort"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

// Health implements kt_health. "networks" is additive: it lists every network
// id the chain-scoped methods accept, so clients can discover support.
func (g *Gateway) Health(_ context.Context, _ json.RawMessage) (any, *rpc.Error) {
	upstreams := make(map[string]upstream.PoolHealth, len(g.evm)+len(g.sol))
	for network, client := range g.evm {
		upstreams[network] = client.Health()
	}
	for network, client := range g.sol {
		upstreams[network] = client.Health()
	}
	return map[string]any{
		"ok":        true,
		"version":   g.cfg.Version,
		"networks":  networkOrder,
		"upstreams": upstreams,
	}, nil
}

// Readiness reports degraded JSON-RPC networks without turning a single-chain
// outage into a whole-service outage. The Gateway remains useful while at
// least one configured pool has an endpoint outside an open circuit; only an
// instance with no usable JSON-RPC network is removed from load-balancer
// rotation. It performs no network I/O.
func (g *Gateway) Readiness() (bool, []string) {
	unavailable := make([]string, 0)
	totalNetworks := 0
	check := func(network string, health upstream.PoolHealth) {
		totalNetworks++
		if health.Endpoints == 0 || health.OpenCircuits >= health.Endpoints {
			unavailable = append(unavailable, network)
		}
	}
	for network, client := range g.evm {
		check(network, client.Health())
	}
	for network, client := range g.sol {
		check(network, client.Health())
	}
	sort.Strings(unavailable)
	return totalNetworks > 0 && len(unavailable) < totalNetworks, unavailable
}

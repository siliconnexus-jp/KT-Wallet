package handlers

import (
	"context"
	"encoding/json"

	"ktwallet/gateway/internal/rpc"
)

// Health implements kt_health. "networks" is additive: it lists every network
// id the chain-scoped methods accept, so clients can discover support.
func (g *Gateway) Health(_ context.Context, _ json.RawMessage) (any, *rpc.Error) {
	return map[string]any{"ok": true, "version": g.cfg.Version, "networks": networkOrder}, nil
}

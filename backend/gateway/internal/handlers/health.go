package handlers

import (
	"context"
	"encoding/json"

	"ktwallet/gateway/internal/rpc"
)

// Health implements kt_health.
func (g *Gateway) Health(_ context.Context, _ json.RawMessage) (any, *rpc.Error) {
	return map[string]any{"ok": true, "version": g.cfg.Version}, nil
}

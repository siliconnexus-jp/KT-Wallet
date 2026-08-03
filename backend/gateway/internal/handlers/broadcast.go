package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

// Broadcast implements kt_broadcast. The payload is forwarded to the chain
// verbatim. Signed-payload fingerprints and terminal outcomes are retained for
// idempotency, but transaction bytes are never stored. Malformed payloads are
// rejected before any upstream call.
func (g *Gateway) Broadcast(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Chain   string `json:"chain"`
		Network string `json:"network"`
		Payload string `json:"payload"`
	}
	if err := decodeStrictJSON(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"chain", "network"?, "payload"}`)
	}
	meta, rpcErr := validateChain(p.Chain)
	if rpcErr != nil {
		return nil, rpcErr
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	if p.Payload == "" {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "payload" is required and must not be blank`)
	}
	canonicalPayload, rpcErr := canonicalBroadcastPayload(meta, p.Chain, p.Payload)
	if rpcErr != nil {
		return nil, rpcErr
	}
	guardKey := broadcastGuardKey(p.Chain, network, canonicalPayload)
	existing, owner, guardErr := g.broadcastGuard.begin(ctx, guardKey)
	if guardErr != nil {
		return nil, &rpc.Error{
			Code:    rpc.CodeSubmissionUnknown,
			Message: "submission_unknown",
			Data: map[string]string{
				"upstream": "gateway",
				"message":  "broadcast idempotency guard unavailable; transaction was not submitted",
			},
		}
	}
	if !owner {
		return replayBroadcast(existing)
	}

	var txHash string
	var err error
	switch {
	case meta.EVM:
		txHash, err = g.evm[network].SendRawTransaction(ctx, p.Payload)
	case p.Chain == "solana":
		txHash, err = g.sol[network].SendTransaction(ctx, p.Payload)
	default: // tron
		trimmed := strings.TrimSpace(p.Payload)
		txHash, err = g.tron[network].Broadcast(ctx, []byte(trimmed))
	}
	if err != nil {
		upstreamName := p.Chain
		if p.Chain == "tron" {
			upstreamName = "trongrid"
		}
		rpcErr := broadcastError(upstreamName, err)
		state := broadcastUnknown
		if rpcErr.Code == rpc.CodeUpstream {
			state = broadcastRejected
		}
		record := broadcastRecord{State: state, Error: rpcErr}
		persistCtx, cancelPersist := context.WithTimeout(context.WithoutCancel(ctx), time.Second)
		persistErr := g.broadcastGuard.complete(persistCtx, guardKey, record)
		cancelPersist()
		if persistErr != nil {
			g.cfg.Log.Error(
				"failed to persist broadcast result",
				"chain", p.Chain,
				"network", network,
				"state", state,
				"err", persistErr,
			)
		}
		return nil, rpcErr
	}
	persistCtx, cancelPersist := context.WithTimeout(context.WithoutCancel(ctx), time.Second)
	persistErr := g.broadcastGuard.complete(persistCtx, guardKey, broadcastRecord{
		State: broadcastAccepted, TxHash: txHash,
	})
	cancelPersist()
	if persistErr != nil {
		g.cfg.Log.Error(
			"failed to persist accepted broadcast result",
			"chain", p.Chain,
			"network", network,
			"err", persistErr,
		)
	}
	return map[string]string{"txHash": txHash}, nil
}

func canonicalBroadcastPayload(
	meta chainMeta,
	chain string,
	payload string,
) ([]byte, *rpc.Error) {
	switch {
	case meta.EVM:
		if !evmHexPayloadRe.MatchString(payload) {
			return nil, rpc.Errorf(rpc.CodeInvalidParams,
				`invalid params: "payload" must be a 0x-prefixed even-length hex string for EVM chains`)
		}
		return []byte(strings.ToLower(payload)), nil
	case chain == "solana":
		raw, err := base64.StdEncoding.DecodeString(payload)
		if err != nil || len(raw) == 0 {
			return nil, rpc.Errorf(rpc.CodeInvalidParams,
				`invalid params: "payload" must be a base64-encoded signed transaction for solana`)
		}
		return raw, nil
	default: // tron
		trimmed := strings.TrimSpace(payload)
		var object map[string]any
		decoder := json.NewDecoder(strings.NewReader(trimmed))
		decoder.UseNumber()
		if !strings.HasPrefix(trimmed, "{") ||
			!json.Valid([]byte(trimmed)) ||
			rejectDuplicateJSONKeys([]byte(trimmed)) != nil ||
			decoder.Decode(&object) != nil || object == nil {
			return nil, rpc.Errorf(rpc.CodeInvalidParams,
				`invalid params: "payload" must be a signed TronGrid transaction JSON object for tron`)
		}
		canonical, err := json.Marshal(object)
		if err != nil {
			return nil, rpc.Errorf(rpc.CodeInvalidParams,
				`invalid params: "payload" must be a signed TronGrid transaction JSON object for tron`)
		}
		return canonical, nil
	}
}

// broadcastError preserves the difference between an explicit node rejection
// and loss of the authoritative answer. Only NodeError proves rejection. Any
// transport/provider failure after a broadcast attempt may hide an accepted
// transaction and therefore becomes submission_unknown, never a retry hint.
func broadcastError(defaultUpstream string, err error) *rpc.Error {
	var ne *upstream.NodeError
	if errors.As(err, &ne) {
		message := upstream.PublicNodeErrorMessage(ne.Message)
		return &rpc.Error{
			Code:    rpc.CodeUpstream,
			Message: message,
			Data:    map[string]string{"upstream": defaultUpstream, "message": message},
		}
	}
	var ua *upstream.Unavailable
	if errors.As(err, &ua) {
		return &rpc.Error{
			Code:    rpc.CodeSubmissionUnknown,
			Message: "submission_unknown",
			Data:    map[string]string{"upstream": defaultUpstream, "message": "upstream response unavailable"},
		}
	}
	return &rpc.Error{
		Code:    rpc.CodeSubmissionUnknown,
		Message: "submission_unknown",
		Data:    map[string]string{"upstream": defaultUpstream, "message": "upstream response unavailable"},
	}
}

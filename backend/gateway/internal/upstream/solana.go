package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"math/big"
	"net/http"
	"time"

	"ktwallet/gateway/internal/clock"
)

// SolanaSignature is the subset of getSignaturesForAddress used by history.
type SolanaSignature struct {
	Signature string          `json:"signature"`
	BlockTime *int64          `json:"blockTime"`
	Err       json.RawMessage `json:"err"`
}

// SolanaAccountImpact is the queried account's native-lamport movement in one
// transaction. Amount is the absolute balance delta, including any fee paid
// by the account.
type SolanaAccountImpact struct {
	Direction string
	Amount    *big.Int
	From      string
	To        string
	Tokens    []SolanaTokenImpact
}

// SolanaTokenImpact is an exact SPL-token raw balance delta owned by the
// queried wallet.
type SolanaTokenImpact struct {
	Mint      string
	Direction string
	Amount    *big.Int
	Decimals  int
	From      string
	To        string
}

// Solana is a Solana JSON-RPC client backed by a failover Pool.
type Solana struct {
	pool *Pool
}

const (
	splTokenProgram     = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
	splToken2022Program = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
)

// NewSolana builds a Solana client over the given RPC URLs.
func NewSolana(urls []string, clk clock.Clock, client *http.Client, attemptTimeout time.Duration) *Solana {
	return &Solana{pool: NewPool("solana", urls, clk, client, attemptTimeout)}
}

func (s *Solana) Health() PoolHealth { return s.pool.Health() }

// GetBalance returns the lamport balance of address.
func (s *Solana) GetBalance(ctx context.Context, address string) (*big.Int, error) {
	raw, err := s.pool.Call(ctx, "getBalance", []any{address})
	if err != nil {
		return nil, err
	}
	var out struct {
		Value json.Number `json:"value"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, &Unavailable{Upstream: "solana", Message: "malformed getBalance result"}
	}
	v, ok := new(big.Int).SetString(out.Value.String(), 10)
	if !ok {
		return nil, &Unavailable{Upstream: "solana", Message: "malformed getBalance value"}
	}
	return v, nil
}

// GetTokenBalance sums every parsed token account owned by address for mint.
// The RPC's mint filter works for both the legacy SPL Token Program and
// Token-2022, so PYUSD does not need a privileged/indexer-only path.
func (s *Solana) GetTokenBalance(ctx context.Context, address, mint string) (*big.Int, error) {
	raw, err := s.pool.Call(ctx, "getTokenAccountsByOwner", []any{
		address,
		map[string]string{"mint": mint},
		map[string]string{"encoding": "jsonParsed", "commitment": "confirmed"},
	})
	if err != nil {
		return nil, err
	}
	var out struct {
		Value []struct {
			Account struct {
				Data struct {
					Parsed struct {
						Info struct {
							TokenAmount struct {
								Amount string `json:"amount"`
							} `json:"tokenAmount"`
						} `json:"info"`
					} `json:"parsed"`
				} `json:"data"`
			} `json:"account"`
		} `json:"value"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, &Unavailable{Upstream: "solana", Message: "malformed token account result"}
	}
	total := new(big.Int)
	for _, account := range out.Value {
		value, ok := new(big.Int).SetString(account.Account.Data.Parsed.Info.TokenAmount.Amount, 10)
		if !ok {
			return nil, &Unavailable{Upstream: "solana", Message: "malformed token account amount"}
		}
		total.Add(total, value)
	}
	return total, nil
}

// GetOwnedTokenAccounts returns legacy SPL and Token-2022 account addresses
// owned by the wallet. Incoming transfers to an existing ATA touch the token
// account, not necessarily the owner public key, so owner-only signature
// history is incomplete.
func (s *Solana) GetOwnedTokenAccounts(ctx context.Context, owner string) ([]string, error) {
	seen := map[string]bool{}
	accounts := make([]string, 0)
	for _, programID := range []string{splTokenProgram, splToken2022Program} {
		raw, err := s.pool.Call(ctx, "getTokenAccountsByOwner", []any{
			owner,
			map[string]string{"programId": programID},
			map[string]string{"encoding": "jsonParsed", "commitment": "confirmed"},
		})
		if err != nil {
			return nil, err
		}
		var out struct {
			Value []struct {
				Pubkey string `json:"pubkey"`
			} `json:"value"`
		}
		if err := json.Unmarshal(raw, &out); err != nil {
			return nil, &Unavailable{Upstream: "solana", Message: "malformed token account result"}
		}
		for _, account := range out.Value {
			if account.Pubkey == "" || seen[account.Pubkey] {
				continue
			}
			seen[account.Pubkey] = true
			accounts = append(accounts, account.Pubkey)
		}
	}
	return accounts, nil
}

// GetSignaturesForAddress returns the newest transaction signatures touching
// address. This is a standard Solana JSON-RPC method and needs no indexer key.
func (s *Solana) GetSignaturesForAddress(ctx context.Context, address string, limit int) ([]SolanaSignature, error) {
	raw, err := s.pool.Call(ctx, "getSignaturesForAddress", []any{
		address,
		map[string]int{"limit": limit},
	})
	if err != nil {
		return nil, err
	}
	var out []SolanaSignature
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, &Unavailable{Upstream: "solana", Message: "malformed getSignaturesForAddress result"}
	}
	return out, nil
}

// SignatureStatus reads confirmation directly from the RPC rather than
// waiting for Helius/history indexing. The returned status is one of
// "confirmed", "failed", "pending", "unknown".
func (s *Solana) SignatureStatus(ctx context.Context, signature string) (string, error) {
	raw, err := s.pool.Call(ctx, "getSignatureStatuses", []any{
		[]string{signature},
		map[string]bool{"searchTransactionHistory": true},
	})
	if err != nil {
		return "", err
	}
	var out struct {
		Value []json.RawMessage `json:"value"`
	}
	if err := json.Unmarshal(raw, &out); err != nil || len(out.Value) == 0 {
		return "", &Unavailable{Upstream: "solana", Message: "malformed signature status"}
	}
	entry := bytes.TrimSpace(out.Value[0])
	if bytes.Equal(entry, []byte("null")) {
		return "unknown", nil
	}
	var status struct {
		Err                json.RawMessage `json:"err"`
		ConfirmationStatus string          `json:"confirmationStatus"`
	}
	if err := json.Unmarshal(entry, &status); err != nil {
		return "", &Unavailable{Upstream: "solana", Message: "malformed signature status entry"}
	}
	trimmedErr := bytes.TrimSpace(status.Err)
	if len(trimmedErr) == 0 {
		return "unknown", nil
	}
	if !bytes.Equal(trimmedErr, []byte("null")) {
		return "failed", nil
	}
	switch status.ConfirmationStatus {
	case "confirmed", "finalized":
		return "confirmed", nil
	case "processed":
		return "pending", nil
	default:
		return "unknown", nil
	}
}

// ExecutionStatus reports explicit success/failure while preserving a missing
// `err` member as unknown. JSON null is positive success evidence in Solana's
// getSignaturesForAddress contract; an absent field is not.
func (s SolanaSignature) ExecutionStatus() ExecutionStatus {
	trimmed := bytes.TrimSpace(s.Err)
	if len(trimmed) == 0 {
		return ExecutionUnknown
	}
	if bytes.Equal(trimmed, []byte("null")) {
		return ExecutionConfirmed
	}
	return ExecutionFailed
}

// GetTransactionAccountImpact resolves native SOL and owned SPL-token balance
// deltas from one parsed transaction. It works even when an incoming token
// transfer touches only the recipient ATA and omits the owner public key from
// the transaction account list.
func (s *Solana) GetTransactionAccountImpact(ctx context.Context, signature, address string) (*SolanaAccountImpact, error) {
	raw, err := s.pool.Call(ctx, "getTransaction", []any{
		signature,
		map[string]any{
			"encoding":                       "jsonParsed",
			"maxSupportedTransactionVersion": 0,
		},
	})
	if err != nil {
		return nil, err
	}
	if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return nil, &Unavailable{Upstream: "solana", Message: "transaction details unavailable"}
	}
	var out struct {
		Meta *struct {
			PreBalances       []json.Number        `json:"preBalances"`
			PostBalances      []json.Number        `json:"postBalances"`
			PreTokenBalances  []solanaTokenBalance `json:"preTokenBalances"`
			PostTokenBalances []solanaTokenBalance `json:"postTokenBalances"`
		} `json:"meta"`
		Transaction struct {
			Message struct {
				AccountKeys  []json.RawMessage `json:"accountKeys"`
				Instructions []json.RawMessage `json:"instructions"`
			} `json:"message"`
		} `json:"transaction"`
	}
	if err := json.Unmarshal(raw, &out); err != nil || out.Meta == nil {
		return nil, &Unavailable{Upstream: "solana", Message: "malformed getTransaction result"}
	}
	index, signer := -1, false
	keys := make([]string, len(out.Transaction.Message.AccountKeys))
	for i, rawKey := range out.Transaction.Message.AccountKeys {
		var key string
		keySigner := false
		if json.Unmarshal(rawKey, &key) != nil {
			var parsed struct {
				Pubkey string `json:"pubkey"`
				Signer bool   `json:"signer"`
			}
			if json.Unmarshal(rawKey, &parsed) != nil {
				continue
			}
			key, keySigner = parsed.Pubkey, parsed.Signer
		}
		keys[i] = key
		if key == address {
			index = i
			signer = keySigner
		}
	}
	delta := new(big.Int)
	direction := "in"
	if index >= 0 && index < len(out.Meta.PreBalances) && index < len(out.Meta.PostBalances) {
		pre, ok := new(big.Int).SetString(out.Meta.PreBalances[index].String(), 10)
		if !ok {
			return nil, &Unavailable{Upstream: "solana", Message: "malformed preBalance"}
		}
		post, ok := new(big.Int).SetString(out.Meta.PostBalances[index].String(), 10)
		if !ok {
			return nil, &Unavailable{Upstream: "solana", Message: "malformed postBalance"}
		}
		delta.Sub(post, pre)
		switch delta.Sign() {
		case -1:
			direction = "out"
			delta.Abs(delta)
		case 0:
			// A zero native delta is common for token/program interactions.
			if signer {
				direction = "out"
			}
		}
	}
	tokenDeltas := map[string]*big.Int{}
	tokenDecimals := map[string]int{}
	applyTokenBalances := func(rows []solanaTokenBalance, sign int64) {
		for _, row := range rows {
			if row.Owner != address || row.Mint == "" {
				continue
			}
			value, ok := new(big.Int).SetString(row.UiTokenAmount.Amount, 10)
			if !ok {
				continue
			}
			if sign < 0 {
				value.Neg(value)
			}
			if tokenDeltas[row.Mint] == nil {
				tokenDeltas[row.Mint] = new(big.Int)
			}
			tokenDeltas[row.Mint].Add(tokenDeltas[row.Mint], value)
			tokenDecimals[row.Mint] = row.UiTokenAmount.Decimals
		}
	}
	applyTokenBalances(out.Meta.PreTokenBalances, -1)
	applyTokenBalances(out.Meta.PostTokenBalances, 1)
	tokenImpacts := make([]SolanaTokenImpact, 0, len(tokenDeltas))
	type tokenAccountIdentity struct {
		owner string
		mint  string
	}
	tokenAccounts := map[string]tokenAccountIdentity{}
	for _, rows := range [][]solanaTokenBalance{out.Meta.PreTokenBalances, out.Meta.PostTokenBalances} {
		for _, row := range rows {
			if row.AccountIndex != nil && *row.AccountIndex >= 0 && *row.AccountIndex < len(keys) && row.Owner != "" && row.Mint != "" {
				tokenAccounts[keys[*row.AccountIndex]] = tokenAccountIdentity{
					owner: row.Owner,
					mint:  row.Mint,
				}
			}
		}
	}
	from, to := "", ""
	partiesByMint := map[string][2]string{}
	for _, rawInstruction := range out.Transaction.Message.Instructions {
		var instruction struct {
			Program string `json:"program"`
			Parsed  *struct {
				Info struct {
					Source      string `json:"source"`
					Destination string `json:"destination"`
					Authority   string `json:"authority"`
				} `json:"info"`
			} `json:"parsed"`
		}
		if json.Unmarshal(rawInstruction, &instruction) != nil || instruction.Parsed == nil {
			continue
		}
		source := instruction.Parsed.Info.Source
		destination := instruction.Parsed.Info.Destination
		if source == "" || destination == "" {
			continue
		}
		if instruction.Program == "system" {
			if source == address || destination == address {
				from, to = source, destination
			}
			continue
		}
		sourceAccount := tokenAccounts[source]
		destinationAccount := tokenAccounts[destination]
		candidateFrom := sourceAccount.owner
		if candidateFrom == "" {
			candidateFrom = instruction.Parsed.Info.Authority
		}
		candidateTo := destinationAccount.owner
		if candidateFrom == address || candidateTo == address {
			mint := sourceAccount.mint
			if mint == "" {
				mint = destinationAccount.mint
			}
			if mint != "" {
				partiesByMint[mint] = [2]string{candidateFrom, candidateTo}
			}
		}
	}
	for mint, tokenDelta := range tokenDeltas {
		if tokenDelta.Sign() == 0 {
			continue
		}
		tokenDirection := "in"
		if tokenDelta.Sign() < 0 {
			tokenDirection = "out"
			tokenDelta.Abs(tokenDelta)
		}
		parties := partiesByMint[mint]
		tokenImpacts = append(tokenImpacts, SolanaTokenImpact{
			Mint:      mint,
			Direction: tokenDirection,
			Amount:    tokenDelta,
			Decimals:  tokenDecimals[mint],
			From:      parties[0],
			To:        parties[1],
		})
	}
	if index < 0 && len(tokenImpacts) == 0 {
		return nil, &Unavailable{Upstream: "solana", Message: "address missing from transaction balances"}
	}
	return &SolanaAccountImpact{
		Direction: direction,
		Amount:    delta,
		From:      from,
		To:        to,
		Tokens:    tokenImpacts,
	}, nil
}

type solanaTokenBalance struct {
	AccountIndex  *int   `json:"accountIndex"`
	Mint          string `json:"mint"`
	Owner         string `json:"owner"`
	UiTokenAmount struct {
		Amount   string `json:"amount"`
		Decimals int    `json:"decimals"`
	} `json:"uiTokenAmount"`
}

// SendTransaction broadcasts a base64-encoded signed transaction and returns
// its signature.
func (s *Solana) SendTransaction(ctx context.Context, payloadBase64 string) (string, error) {
	raw, err := s.pool.CallOnce(ctx, "sendTransaction", []any{payloadBase64, map[string]string{"encoding": "base64"}})
	if err != nil {
		return "", err
	}
	var sig string
	if err := json.Unmarshal(raw, &sig); err != nil {
		return "", &Unavailable{Upstream: "solana", Message: "malformed sendTransaction result"}
	}
	return sig, nil
}

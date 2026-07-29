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
	Tokens    []SolanaTokenImpact
}

// SolanaTokenImpact is an exact SPL-token raw balance delta owned by the
// queried wallet.
type SolanaTokenImpact struct {
	Mint      string
	Direction string
	Amount    *big.Int
	Decimals  int
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
		return nil, &Unavailable{Upstream: "solana", Message: "malformed getBalance value: " + out.Value.String()}
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

// Failed reports whether the signature status contains a non-null error.
func (s SolanaSignature) Failed() bool {
	trimmed := bytes.TrimSpace(s.Err)
	return len(trimmed) != 0 && !bytes.Equal(trimmed, []byte("null"))
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
				AccountKeys []json.RawMessage `json:"accountKeys"`
			} `json:"message"`
		} `json:"transaction"`
	}
	if err := json.Unmarshal(raw, &out); err != nil || out.Meta == nil {
		return nil, &Unavailable{Upstream: "solana", Message: "malformed getTransaction result"}
	}
	index, signer := -1, false
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
		if key == address {
			index = i
			signer = keySigner
			break
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
	for mint, tokenDelta := range tokenDeltas {
		if tokenDelta.Sign() == 0 {
			continue
		}
		tokenDirection := "in"
		if tokenDelta.Sign() < 0 {
			tokenDirection = "out"
			tokenDelta.Abs(tokenDelta)
		}
		tokenImpacts = append(tokenImpacts, SolanaTokenImpact{
			Mint:      mint,
			Direction: tokenDirection,
			Amount:    tokenDelta,
			Decimals:  tokenDecimals[mint],
		})
	}
	if index < 0 && len(tokenImpacts) == 0 {
		return nil, &Unavailable{Upstream: "solana", Message: "address missing from transaction balances"}
	}
	return &SolanaAccountImpact{
		Direction: direction,
		Amount:    delta,
		Tokens:    tokenImpacts,
	}, nil
}

type solanaTokenBalance struct {
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
	raw, err := s.pool.Call(ctx, "sendTransaction", []any{payloadBase64, map[string]string{"encoding": "base64"}})
	if err != nil {
		return "", err
	}
	var sig string
	if err := json.Unmarshal(raw, &sig); err != nil {
		return "", &Unavailable{Upstream: "solana", Message: "malformed sendTransaction result"}
	}
	return sig, nil
}

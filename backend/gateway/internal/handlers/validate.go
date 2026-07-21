package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"math/big"
	"regexp"
	"strings"

	"ktwallet/gateway/internal/rpc"
)

type chainMeta struct {
	Symbol   string
	Decimals int
	EVM      bool
}

var chains = map[string]chainMeta{
	"eth":     {Symbol: "ETH", Decimals: 18, EVM: true},
	"polygon": {Symbol: "POL", Decimals: 18, EVM: true},
	"tron":    {Symbol: "TRX", Decimals: 6},
	"solana":  {Symbol: "SOL", Decimals: 9},
}

var evmAddressRe = regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
var evmHexPayloadRe = regexp.MustCompile(`^0x(?:[0-9a-fA-F]{2})+$`)

func validateChain(chain string) (chainMeta, *rpc.Error) {
	m, ok := chains[chain]
	if !ok {
		return chainMeta{}, rpc.Errorf(rpc.CodeInvalidParams,
			`invalid params: "chain" must be one of "eth", "polygon", "tron", "solana"`)
	}
	return m, nil
}

func validateAddress(chain, address string) *rpc.Error {
	if strings.TrimSpace(address) == "" {
		return rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "address" is required and must not be blank`)
	}
	if chains[chain].EVM && !evmAddressRe.MatchString(address) {
		return rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "address" must be a 0x-prefixed 20-byte hex address`)
	}
	return nil
}

// tokenSetHash canonically fingerprints a token list for balance cache keys.
func tokenSetHash(tokens []tokenRef) string {
	items := make([]string, len(tokens))
	for i, t := range tokens {
		items[i] = t.Contract + "\x00" + big.NewInt(int64(t.Decimals)).String() + "\x00" + t.Symbol
	}
	// Order matters for the response, but not for identity: sort a copy.
	sorted := append([]string(nil), items...)
	for i := 1; i < len(sorted); i++ {
		for j := i; j > 0 && sorted[j] < sorted[j-1]; j-- {
			sorted[j], sorted[j-1] = sorted[j-1], sorted[j]
		}
	}
	h := sha256.Sum256([]byte(strings.Join(sorted, "\n")))
	return hex.EncodeToString(h[:])
}

// newDecimal parses a base-10 integer string, reporting validity.
func newDecimal(s string) (*big.Int, bool) {
	v, ok := new(big.Int).SetString(s, 10)
	return v, ok
}

// --- TRON address normalization -------------------------------------------
//
// TronGrid mixes address encodings: TRC-20 endpoints return base58check
// (T...), native transaction endpoints return 41-prefixed hex. To determine
// transfer direction we normalize both to lowercase hex.

const b58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

var b58Index = func() [256]int8 {
	var idx [256]int8
	for i := range idx {
		idx[i] = -1
	}
	for i := 0; i < len(b58Alphabet); i++ {
		idx[b58Alphabet[i]] = int8(i)
	}
	return idx
}()

func base58Decode(s string) ([]byte, bool) {
	n := new(big.Int)
	fiftyEight := big.NewInt(58)
	for i := 0; i < len(s); i++ {
		d := b58Index[s[i]]
		if d < 0 {
			return nil, false
		}
		n.Mul(n, fiftyEight)
		n.Add(n, big.NewInt(int64(d)))
	}
	b := n.Bytes()
	// Restore leading zero bytes (encoded as leading '1's).
	zeros := 0
	for zeros < len(s) && s[zeros] == '1' {
		zeros++
	}
	return append(make([]byte, zeros), b...), true
}

// tronAddrHex normalizes a TRON address (base58check T... or 41-hex) to
// lowercase 41-prefixed hex for comparison. Unrecognized inputs are returned
// lowercased so comparisons stay deterministic.
func tronAddrHex(addr string) string {
	if len(addr) == 42 && strings.HasPrefix(strings.ToLower(addr), "41") {
		if _, err := hex.DecodeString(addr); err == nil {
			return strings.ToLower(addr)
		}
	}
	if strings.HasPrefix(addr, "T") {
		if raw, ok := base58Decode(addr); ok && len(raw) == 25 {
			payload, checksum := raw[:21], raw[21:]
			h1 := sha256.Sum256(payload)
			h2 := sha256.Sum256(h1[:])
			if h2[0] == checksum[0] && h2[1] == checksum[1] && h2[2] == checksum[2] && h2[3] == checksum[3] {
				return strings.ToLower(hex.EncodeToString(payload))
			}
		}
	}
	return strings.ToLower(addr)
}

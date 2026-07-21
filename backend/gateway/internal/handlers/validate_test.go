package handlers

import "testing"

// Verified pair: base58check(41b0f28f...) == TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C.
// TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t is the well-known USDT TRC-20 contract.
func TestTronAddrHex(t *testing.T) {
	cases := []struct{ in, want string }{
		{"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C", "41b0f28f797f0e57e56c1729783b7a5e5d4bacd0f4"},
		{"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", "41a614f803b6fd780986a42c78ec9c7f77e6ded13c"},
		{"41B0F28F797F0E57E56C1729783B7A5E5D4BACD0F4", "41b0f28f797f0e57e56c1729783b7a5e5d4bacd0f4"},
		{"41b0f28f797f0e57e56c1729783b7a5e5d4bacd0f4", "41b0f28f797f0e57e56c1729783b7a5e5d4bacd0f4"},
		// bad checksum: falls back to lowercased passthrough
		{"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4D", "ts6pwdwckryfzfzdmgup7vzjvhyhfq4c4d"},
		// invalid base58 characters (0, O, I, l)
		{"T0OIl", "t0oil"},
	}
	for _, tc := range cases {
		if got := tronAddrHex(tc.in); got != tc.want {
			t.Errorf("tronAddrHex(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestTokenSetHash(t *testing.T) {
	a := []tokenRef{{Contract: "0xaaa", Decimals: 6, Symbol: "USDT"}}
	b := []tokenRef{{Contract: "0xbbb", Decimals: 6, Symbol: "USDC"}}
	both := []tokenRef{a[0], b[0]}
	bothReversed := []tokenRef{b[0], a[0]}

	if tokenSetHash(a) == tokenSetHash(b) {
		t.Fatal("different tokens must hash differently")
	}
	if tokenSetHash(a) == tokenSetHash(both) {
		t.Fatal("subset must hash differently from superset")
	}
	if tokenSetHash(both) != tokenSetHash(bothReversed) {
		t.Fatal("token order must not change the set identity")
	}
	if tokenSetHash(nil) != tokenSetHash([]tokenRef{}) {
		t.Fatal("nil and empty token sets are the same set")
	}
	// Decimals participate in identity.
	c := []tokenRef{{Contract: "0xaaa", Decimals: 18, Symbol: "USDT"}}
	if tokenSetHash(a) == tokenSetHash(c) {
		t.Fatal("decimals must participate in the tokenset hash")
	}
}

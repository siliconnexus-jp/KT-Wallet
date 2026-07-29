package handlers

import (
	"path/filepath"
	"testing"
)

func TestDefaultAndCheckedInOfficialTokenCatalogsMatch(t *testing.T) {
	checkedIn, err := LoadOfficialTokensFile(
		filepath.Join("..", "..", "config", "official-tokens.json"),
	)
	if err != nil {
		t.Fatal(err)
	}
	defaults, err := normalizeOfficialTokens(defaultOfficialTokens())
	if err != nil {
		t.Fatal(err)
	}

	type identity struct {
		network  string
		contract string
	}
	index := func(tokens []OfficialToken) map[identity]OfficialToken {
		out := make(map[identity]OfficialToken, len(tokens))
		for _, token := range tokens {
			key := identity{network: token.Network, contract: token.Contract}
			if _, exists := out[key]; exists {
				t.Fatalf("duplicate token identity: %+v", key)
			}
			out[key] = token
		}
		return out
	}
	want := index(checkedIn)
	got := index(defaults)
	if len(got) != len(want) {
		t.Fatalf("default token count = %d, checked-in count = %d", len(got), len(want))
	}
	for key, expected := range want {
		actual, ok := got[key]
		if !ok {
			t.Errorf("default catalog missing %+v", key)
			continue
		}
		if actual.Symbol != expected.Symbol || actual.Decimals != expected.Decimals {
			t.Errorf(
				"%+v metadata = %s/%d, want %s/%d",
				key,
				actual.Symbol,
				actual.Decimals,
				expected.Symbol,
				expected.Decimals,
			)
		}
	}
}

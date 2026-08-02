package upstream

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestCredentialBearingTransportErrorsAreRedactedAcrossClients(t *testing.T) {
	const secret = "provider-key-must-never-leave-gateway"
	client := &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		return nil, fmt.Errorf("dial %s: credential=%s", req.URL.String(), secret)
	})}
	address := "0x1111111111111111111111111111111111111111"

	cases := []struct {
		name string
		call func() error
	}{
		{
			name: "CoinGecko",
			call: func() error {
				_, err := NewCoinGecko("https://prices.example.invalid/"+secret, client, nil, time.Second).
					SimplePrice(context.Background(), []string{"ethereum"})
				return err
			},
		},
		{
			name: "Etherscan",
			call: func() error {
				_, err := NewEtherscan("https://scan.example.invalid/api", secret, client, time.Second).
					TxList(context.Background(), 1, address, 20)
				return err
			},
		},
		{
			name: "Helius",
			call: func() error {
				_, err := NewHelius("https://helius.example.invalid/v0/"+secret, secret, client, time.Second).
					Transfers(context.Background(), "11111111111111111111111111111111", 20)
				return err
			},
		},
		{
			name: "Alchemy",
			call: func() error {
				_, err := NewAlchemy([]string{"https://rpc.example.invalid/v2/" + secret}, client, time.Second).
					Transfers(context.Background(), address, 20)
				return err
			},
		},
		{
			name: "TronGrid",
			call: func() error {
				_, err := NewTron("https://tron.example.invalid/"+secret, client, time.Second).
					GetAccount(context.Background(), "TJRabPrwbZy45sbavfcjinPJC18kjpRTv8")
				return err
			},
		},
		{
			name: "GoPlus",
			call: func() error {
				_, err := NewGoPlus("https://goplus.example.invalid/api", secret, client, time.Second).
					TokenRisk(context.Background(), "1", address)
				return err
			},
		},
		{
			name: "GoPlus approvals",
			call: func() error {
				_, err := NewGoPlusApprovals("https://goplus.example.invalid/approvals", secret, client, time.Second).
					TokenApprovals(context.Background(), "1", address)
				return err
			},
		},
		{
			name: "GoPlus Solana",
			call: func() error {
				_, err := NewGoPlusSolana("https://goplus.example.invalid/solana", secret, client, time.Second).
					TokenRisk(context.Background(), "11111111111111111111111111111111")
				return err
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.call()
			if err == nil {
				t.Fatal("expected transport failure")
			}
			if strings.Contains(err.Error(), secret) {
				t.Fatalf("credential escaped through error: %v", err)
			}
			var unavailable *Unavailable
			if !errors.As(err, &unavailable) {
				t.Fatalf("expected Unavailable, got %T: %v", err, err)
			}
		})
	}
}

func TestPublicNodeErrorMessageNeverReflectsUnknownProviderText(t *testing.T) {
	const secret = "https://rpc.example.invalid/v2/provider-secret"
	if got := PublicNodeErrorMessage("provider internal failure at " + secret); strings.Contains(got, secret) {
		t.Fatalf("unknown provider text was reflected: %q", got)
	} else if got != "upstream rejected request" {
		t.Fatalf("unexpected normalized message: %q", got)
	}
	if got := (&NodeError{Code: -32000, Message: "provider internal failure at " + secret}).Error(); strings.Contains(got, secret) {
		t.Fatalf("generic NodeError formatting reflected provider text: %q", got)
	}
}

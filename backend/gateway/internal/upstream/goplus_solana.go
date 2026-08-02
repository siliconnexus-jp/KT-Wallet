package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// GoPlusSolana queries the provider's separate Solana Token Security API.
// Only a public mint address leaves the Gateway. Capability flags such as
// mintable/freezable are not treated as proof of malice: legitimate assets
// including USDC use them. KT Wallet blocks only when the provider explicitly
// marks a privileged authority as malicious.
type GoPlusSolana struct {
	baseURL     string
	accessToken string
	client      *http.Client
	timeout     time.Duration
}

func NewGoPlusSolana(
	baseURL string,
	accessToken string,
	client *http.Client,
	attemptTimeout time.Duration,
) *GoPlusSolana {
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &GoPlusSolana{
		baseURL:     strings.TrimSpace(baseURL),
		accessToken: strings.TrimSpace(accessToken),
		client:      client,
		timeout:     attemptTimeout,
	}
}

func (g *GoPlusSolana) TokenRisk(ctx context.Context, mint string) (TokenThreat, error) {
	if err := ValidateGoPlusURL(g.baseURL); err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "invalid provider endpoint"}
	}
	endpoint, err := url.Parse(g.baseURL)
	if err != nil || endpoint.Scheme == "" || endpoint.Host == "" {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "invalid provider endpoint"}
	}
	query := endpoint.Query()
	query.Set("contract_addresses", mint)
	endpoint.RawQuery = query.Encode()

	requestCtx, cancel := context.WithTimeout(ctx, g.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(requestCtx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "could not create request"}
	}
	if g.accessToken != "" {
		req.Header.Set("Authorization", "Bearer "+g.accessToken)
	}
	req.Header.Set("Accept", "application/json")
	client := *g.client
	client.CheckRedirect = func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}
	resp, err := client.Do(req)
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "request failed"}
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return TokenThreat{}, &Unavailable{
			Upstream: "goplus-solana",
			Message:  fmt.Sprintf("provider returned HTTP %d", resp.StatusCode),
		}
	}
	data, err := readBoundedResponse(resp.Body, maxGoPlusResponseBytes)
	if errors.Is(err, errResponseTooLarge) {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "provider response too large"}
	}
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "could not read provider response"}
	}
	var envelope struct {
		Code   int                        `json:"code"`
		Result map[string]json.RawMessage `json:"result"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed or incomplete provider response"}
	}
	if envelope.Code == 2020 || envelope.Code == 2021 {
		return TokenThreat{Found: false}, nil
	}
	if envelope.Code != 1 || envelope.Result == nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed or incomplete provider response"}
	}
	recordRaw, found := envelope.Result[mint]
	if !found || len(bytes.TrimSpace(recordRaw)) == 0 || bytes.Equal(bytes.TrimSpace(recordRaw), []byte("null")) {
		return TokenThreat{Found: false}, nil
	}
	var record map[string]json.RawMessage
	if err := json.Unmarshal(recordRaw, &record); err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed token risk record"}
	}
	unsafe, err := explicitSolanaAuthorityThreat(record)
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed token risk record"}
	}
	category := ""
	if unsafe {
		category = "malicious"
	}
	return TokenThreat{Found: true, Unsafe: unsafe, Category: category}, nil
}

var solanaPrivilegedRiskFields = [...]string{
	"creator",
	"metadata_mutable",
	"mintable",
	"freezable",
	"closable",
	"transfer_fee_upgradable",
	"default_account_state_upgradable",
	"balance_mutable_authority",
	"transfer_hook",
	"transfer_hook_upgradable",
}

func explicitSolanaAuthorityThreat(record map[string]json.RawMessage) (bool, error) {
	for _, field := range solanaPrivilegedRiskFields {
		raw, ok := record[field]
		if !ok || len(bytes.TrimSpace(raw)) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			continue
		}
		var value any
		if err := json.Unmarshal(raw, &value); err != nil {
			return false, err
		}
		unsafe, err := containsMaliciousAuthority(value, 0)
		if err != nil {
			return false, err
		}
		if unsafe {
			return true, nil
		}
	}
	return false, nil
}

func containsMaliciousAuthority(value any, depth int) (bool, error) {
	if depth > 8 {
		return false, fmt.Errorf("provider authority object is too deeply nested")
	}
	switch value := value.(type) {
	case map[string]any:
		if flag, ok := value["malicious_address"]; ok {
			switch flag := flag.(type) {
			case string:
				if flag != "0" && flag != "1" {
					return false, fmt.Errorf("invalid malicious_address flag")
				}
				if flag == "1" {
					return true, nil
				}
			case float64:
				if flag != 0 && flag != 1 {
					return false, fmt.Errorf("invalid malicious_address flag")
				}
				if flag == 1 {
					return true, nil
				}
			case bool:
				if flag {
					return true, nil
				}
			default:
				return false, fmt.Errorf("invalid malicious_address flag")
			}
		}
		for _, child := range value {
			unsafe, err := containsMaliciousAuthority(child, depth+1)
			if err != nil || unsafe {
				return unsafe, err
			}
		}
	case []any:
		for _, child := range value {
			unsafe, err := containsMaliciousAuthority(child, depth+1)
			if err != nil || unsafe {
				return unsafe, err
			}
		}
	}
	return false, nil
}

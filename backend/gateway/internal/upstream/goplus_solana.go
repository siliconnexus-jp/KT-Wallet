package upstream

import (
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
	if err := validateSolanaMint(mint); err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "invalid token identity"}
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
	envelope, err := decodeGoPlusEnvelope(data)
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed or incomplete provider response"}
	}
	if envelope.Code == 2020 || envelope.Code == 2021 {
		if !isJSONNull(envelope.Result) {
			return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed or incomplete provider response"}
		}
		return TokenThreat{Found: false}, nil
	}
	if envelope.Code != 1 {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed or incomplete provider response"}
	}
	recordRaw, found, err := decodeBoundGoPlusRecord(envelope.Result, mint, false)
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed or incomplete provider response"}
	}
	if !found {
		return TokenThreat{Found: false}, nil
	}
	unsafe, err := explicitSolanaAuthorityThreat(recordRaw)
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus-solana", Message: "malformed token risk record"}
	}
	category := ""
	if unsafe {
		category = "malicious"
	}
	return TokenThreat{Found: true, Unsafe: unsafe, Category: category}, nil
}

type solanaPrivilegedRiskField struct {
	name         string
	authorityKey string
	array        bool
}

var solanaPrivilegedRiskFields = [...]solanaPrivilegedRiskField{
	{name: "creators", array: true},
	{name: "metadata_mutable", authorityKey: "metadata_upgrade_authority"},
	{name: "mintable", authorityKey: "authority"},
	{name: "freezable", authorityKey: "authority"},
	{name: "closable", authorityKey: "authority"},
	{name: "transfer_fee_upgradable", authorityKey: "authority"},
	{name: "default_account_state_upgradable", authorityKey: "authority"},
	{name: "balance_mutable_authority", authorityKey: "authority"},
	{name: "transfer_hook", array: true},
	{name: "transfer_hook_upgradable", authorityKey: "authority"},
}

func explicitSolanaAuthorityThreat(recordRaw json.RawMessage) (bool, error) {
	record, err := decodeUniqueJSONObject(recordRaw)
	if err != nil {
		return false, err
	}
	consumed := make([]string, 0, len(solanaPrivilegedRiskFields))
	for _, field := range solanaPrivilegedRiskFields {
		consumed = append(consumed, field.name)
	}
	if err := rejectConsumedFieldAliases(record, consumed...); err != nil {
		return false, err
	}
	unsafe := false
	for _, field := range solanaPrivilegedRiskFields {
		raw, present := record[field.name]
		if !present || isJSONNull(raw) {
			return false, fmt.Errorf("missing Solana risk field %q", field.name)
		}
		var fieldUnsafe bool
		if field.array {
			fieldUnsafe, err = parseSolanaAuthorityArray(raw)
		} else {
			fieldUnsafe, err = parseSolanaCapability(raw, field.authorityKey)
		}
		if err != nil {
			return false, err
		}
		unsafe = unsafe || fieldUnsafe
	}
	return unsafe, nil
}

func parseSolanaCapability(raw json.RawMessage, authorityKey string) (bool, error) {
	fields, err := decodeExactJSONObject(raw, "status", authorityKey)
	if err != nil {
		return false, err
	}
	statusRaw, hasStatus := fields["status"]
	authorityRaw, hasAuthority := fields[authorityKey]
	if !hasStatus || !hasAuthority {
		return false, errors.New("incomplete Solana capability record")
	}
	if _, err := parseBinaryFlag(statusRaw); err != nil {
		return false, err
	}
	return parseSolanaAuthorityArray(authorityRaw)
}

func parseSolanaAuthorityArray(raw json.RawMessage) (bool, error) {
	rows, err := decodeRawJSONArray(raw, maxGoPlusAuthorityRows)
	if err != nil {
		return false, err
	}
	unsafe := false
	for _, row := range rows {
		fields, err := decodeExactJSONObject(row, "address", "malicious_address")
		if err != nil {
			return false, err
		}
		addressRaw, hasAddress := fields["address"]
		maliciousRaw, hasMalicious := fields["malicious_address"]
		if !hasAddress || !hasMalicious {
			return false, errors.New("incomplete Solana authority record")
		}
		address, err := decodeBoundedString(addressRaw, 44, false)
		if err != nil || validateSolanaMint(address) != nil {
			return false, errors.New("invalid Solana authority address")
		}
		malicious, err := parseBinaryFlag(maliciousRaw)
		if err != nil {
			return false, err
		}
		unsafe = unsafe || malicious
	}
	return unsafe, nil
}

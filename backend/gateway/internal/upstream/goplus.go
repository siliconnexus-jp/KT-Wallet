package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const maxGoPlusResponseBytes = 2 << 20

// TokenThreat is the deliberately narrow conclusion KT Wallet accepts from
// an external token-intelligence provider. Found only means the provider
// returned a record for the exact contract; it never means the token is safe.
type TokenThreat struct {
	Found    bool
	Unsafe   bool
	Category string
}

// GoPlus queries the public Token Security API. Only public chain ids and
// contract addresses leave the Gateway; wallet addresses, balances and
// transaction payloads are never part of this request.
type GoPlus struct {
	baseURL     string
	accessToken string
	client      *http.Client
	timeout     time.Duration
}

func NewGoPlus(baseURL, accessToken string, client *http.Client, attemptTimeout time.Duration) *GoPlus {
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &GoPlus{
		baseURL:     strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		accessToken: strings.TrimSpace(accessToken),
		client:      client,
		timeout:     attemptTimeout,
	}
}

// ValidateGoPlusURL rejects configurations that could expose a bearer token
// over plaintext transport or hide credentials/alternate targets in the URL.
// Loopback HTTP remains available for local development and deterministic
// tests. Errors deliberately omit the supplied URL.
func ValidateGoPlusURL(raw string) error {
	trimmed := strings.TrimSpace(raw)
	parsed, err := url.Parse(trimmed)
	if err != nil || parsed.Host == "" || parsed.Scheme == "" || parsed.User != nil {
		return errors.New("invalid token risk provider endpoint")
	}
	if strings.Contains(trimmed, "#") || parsed.RawQuery != "" {
		return errors.New("invalid token risk provider endpoint")
	}
	switch strings.ToLower(parsed.Scheme) {
	case "https":
		return nil
	case "http":
		host := strings.ToLower(parsed.Hostname())
		if host == "localhost" {
			return nil
		}
		if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
			return nil
		}
	}
	return errors.New("token risk provider endpoint must use HTTPS")
}

// TokenRisk returns explicit high-confidence malicious evidence only. Many
// legitimate tokens are mintable, pausable, proxy-based or have blacklist
// controls, so those capability flags must not be promoted to "unsafe".
func (g *GoPlus) TokenRisk(ctx context.Context, chainID, contract string) (TokenThreat, error) {
	if err := ValidateGoPlusURL(g.baseURL); err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "invalid provider endpoint"}
	}
	endpoint, err := url.Parse(g.baseURL + "/" + url.PathEscape(chainID))
	if err != nil || endpoint.Scheme == "" || endpoint.Host == "" {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "invalid provider endpoint"}
	}
	query := endpoint.Query()
	query.Set("contract_addresses", contract)
	endpoint.RawQuery = query.Encode()

	requestCtx, cancel := context.WithTimeout(ctx, g.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(requestCtx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "could not create request"}
	}
	if g.accessToken != "" {
		req.Header.Set("Authorization", "Bearer "+g.accessToken)
	}
	req.Header.Set("Accept", "application/json")
	// Never forward an optional bearer token through an HTTP redirect. A
	// provider endpoint change must be an explicit, validated configuration
	// update rather than an instruction supplied by an upstream response.
	client := *g.client
	client.CheckRedirect = func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}
	resp, err := client.Do(req)
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "request failed"}
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return TokenThreat{}, &Unavailable{
			Upstream: "goplus",
			Message:  fmt.Sprintf("provider returned HTTP %d", resp.StatusCode),
		}
	}
	data, err := readBoundedResponse(resp.Body, maxGoPlusResponseBytes)
	if errors.Is(err, errResponseTooLarge) {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "provider response too large"}
	}
	if err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "could not read provider response"}
	}
	var envelope struct {
		Code   int                        `json:"code"`
		Result map[string]json.RawMessage `json:"result"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "malformed or incomplete provider response"}
	}
	// The provider documents 2020 (not a contract) and 2021 (no information)
	// as valid no-data outcomes. They do not establish safety.
	if envelope.Code == 2020 || envelope.Code == 2021 {
		return TokenThreat{Found: false}, nil
	}
	if envelope.Code != 1 || envelope.Result == nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "malformed or incomplete provider response"}
	}
	lookupKey := contract
	if strings.HasPrefix(strings.ToLower(contract), "0x") {
		lookupKey = strings.ToLower(contract)
	}
	recordRaw, found := envelope.Result[lookupKey]
	if !found && strings.HasPrefix(lookupKey, "0x") {
		for key, value := range envelope.Result {
			if strings.EqualFold(key, contract) {
				recordRaw, found = value, true
				break
			}
		}
	}
	if !found || len(bytes.TrimSpace(recordRaw)) == 0 || bytes.Equal(bytes.TrimSpace(recordRaw), []byte("null")) {
		return TokenThreat{Found: false}, nil
	}
	var record map[string]any
	if err := json.Unmarshal(recordRaw, &record); err != nil {
		return TokenThreat{}, &Unavailable{Upstream: "goplus", Message: "malformed token risk record"}
	}
	category := explicitTokenThreatCategory(record)
	return TokenThreat{
		Found:    true,
		Unsafe:   category != "",
		Category: category,
	}, nil
}

func explicitTokenThreatCategory(record map[string]any) string {
	if flagIsOne(record["is_honeypot"]) || flagIsOne(record["honeypot_with_same_creator"]) {
		return "honeypot"
	}
	if flagIsOne(record["fake_token"]) {
		return "impersonation"
	}
	if flagIsOne(record["malicious_address"]) || flagIsOne(record["gas_abuse"]) {
		return "malicious"
	}
	return ""
}

func flagIsOne(value any) bool {
	switch value := value.(type) {
	case string:
		return strings.TrimSpace(value) == "1"
	case float64:
		return value == 1
	case bool:
		return value
	default:
		return false
	}
}

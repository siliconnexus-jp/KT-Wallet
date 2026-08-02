package upstream

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const maxGoPlusApprovalRows = 500

var (
	evmAddressPattern = regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
	txHashPattern     = regexp.MustCompile(`^0x[0-9a-fA-F]{64}$`)
	decimalPattern    = regexp.MustCompile(`^[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$`)
)

// TokenApproval is one outstanding ERC-20 allowance. Every string is bounded
// and sanitized before it leaves the upstream package; provider names and
// symbols are display hints only and never establish token or spender safety.
type TokenApproval struct {
	TokenAddress   string
	TokenName      string
	TokenSymbol    string
	Decimals       int
	Balance        string
	TokenRisky     bool
	Spender        string
	SpenderName    string
	SpenderTag     string
	SpenderRisky   bool
	SpenderTrusted bool
	Amount         string
	Unlimited      bool
	ApprovedAt     int64
	Transaction    string
}

// GoPlusApprovals queries the opt-in Approval Management API. Unlike token
// metadata checks, this endpoint receives a public wallet address. Callers
// must obtain explicit user consent before invoking TokenApprovals.
type GoPlusApprovals struct {
	baseURL     string
	accessToken string
	client      *http.Client
	timeout     time.Duration
}

func NewGoPlusApprovals(
	baseURL, accessToken string,
	client *http.Client,
	attemptTimeout time.Duration,
) *GoPlusApprovals {
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &GoPlusApprovals{
		baseURL:     strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		accessToken: strings.TrimSpace(accessToken),
		client:      client,
		timeout:     attemptTimeout,
	}
}

// TokenApprovals returns the provider's complete outstanding ERC-20 approval
// list or an error. Partial/malformed responses never degrade to an empty list
// because "no approvals" is a security-relevant conclusion.
func (g *GoPlusApprovals) TokenApprovals(
	ctx context.Context,
	chainID, address string,
) ([]TokenApproval, error) {
	if err := ValidateGoPlusURL(g.baseURL); err != nil {
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "invalid provider endpoint"}
	}
	if !evmAddressPattern.MatchString(address) {
		return nil, errors.New("invalid EVM owner address")
	}
	endpoint, err := url.Parse(g.baseURL + "/" + url.PathEscape(chainID))
	if err != nil || endpoint.Scheme == "" || endpoint.Host == "" {
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "invalid provider endpoint"}
	}
	query := endpoint.Query()
	query.Set("addresses", strings.ToLower(address))
	endpoint.RawQuery = query.Encode()

	requestCtx, cancel := context.WithTimeout(ctx, g.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(requestCtx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "could not create request"}
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
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "request failed"}
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{
			Upstream: "goplus-approvals",
			Message:  fmt.Sprintf("provider returned HTTP %d", resp.StatusCode),
		}
	}
	data, err := readBoundedResponse(resp.Body, maxGoPlusResponseBytes)
	if errors.Is(err, errResponseTooLarge) {
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "provider response too large"}
	}
	if err != nil {
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "could not read provider response"}
	}

	var envelope approvalEnvelope
	if err := json.Unmarshal(data, &envelope); err != nil ||
		envelope.Code != 1 || envelope.Result == nil {
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "malformed or incomplete provider response"}
	}
	rows := make([]TokenApproval, 0)
	for _, token := range envelope.Result {
		parsed, err := parseApprovalToken(token)
		if err != nil {
			return nil, &Unavailable{Upstream: "goplus-approvals", Message: "malformed approval record"}
		}
		if len(rows)+len(parsed) > maxGoPlusApprovalRows {
			return nil, &Unavailable{Upstream: "goplus-approvals", Message: "provider returned too many approvals"}
		}
		rows = append(rows, parsed...)
	}
	return rows, nil
}

type approvalEnvelope struct {
	Code   int                   `json:"code"`
	Result []approvalTokenRecord `json:"result"`
}

type approvalTokenRecord struct {
	TokenAddress     string                   `json:"token_address"`
	TokenName        string                   `json:"token_name"`
	TokenSymbol      string                   `json:"token_symbol"`
	Decimals         json.RawMessage          `json:"decimals"`
	Balance          string                   `json:"balance"`
	MaliciousAddress json.RawMessage          `json:"malicious_address"`
	Malicious        []string                 `json:"malicious_behavior"`
	Approved         []approvalContractRecord `json:"approved_list"`
}

type approvalContractRecord struct {
	Contract    string              `json:"approved_contract"`
	Amount      string              `json:"approved_amount"`
	ApprovedAt  json.RawMessage     `json:"approved_time"`
	Transaction string              `json:"hash"`
	AddressInfo approvalAddressInfo `json:"address_info"`
}

type approvalAddressInfo struct {
	ContractName string          `json:"contract_name"`
	Tag          string          `json:"tag"`
	DoubtList    json.RawMessage `json:"doubt_list"`
	TrustList    json.RawMessage `json:"trust_list"`
	Malicious    []string        `json:"malicious_behavior"`
}

func parseApprovalToken(token approvalTokenRecord) ([]TokenApproval, error) {
	if !evmAddressPattern.MatchString(token.TokenAddress) {
		return nil, errors.New("invalid token address")
	}
	decimals, ok := boundedJSONInt(token.Decimals, 0, 255)
	if !ok || !validProviderDecimal(token.Balance) {
		return nil, errors.New("invalid token metadata")
	}
	tokenRisky := rawFlagIsOne(token.MaliciousAddress) || len(token.Malicious) > 0
	rows := make([]TokenApproval, 0, len(token.Approved))
	for _, approval := range token.Approved {
		if !evmAddressPattern.MatchString(approval.Contract) {
			return nil, errors.New("invalid spender address")
		}
		unlimited := strings.EqualFold(strings.TrimSpace(approval.Amount), "Unlimited")
		if !unlimited && !validProviderDecimal(approval.Amount) {
			return nil, errors.New("invalid approval amount")
		}
		approvedAt, ok := boundedJSONInt64(approval.ApprovedAt, 0, 1<<62)
		if !ok || (approval.Transaction != "" && !txHashPattern.MatchString(approval.Transaction)) {
			return nil, errors.New("invalid approval evidence")
		}
		rows = append(rows, TokenApproval{
			TokenAddress:   strings.ToLower(token.TokenAddress),
			TokenName:      boundedDisplayText(token.TokenName, 80),
			TokenSymbol:    boundedDisplayText(token.TokenSymbol, 32),
			Decimals:       decimals,
			Balance:        strings.TrimSpace(token.Balance),
			TokenRisky:     tokenRisky,
			Spender:        strings.ToLower(approval.Contract),
			SpenderName:    boundedDisplayText(approval.AddressInfo.ContractName, 80),
			SpenderTag:     boundedDisplayText(approval.AddressInfo.Tag, 80),
			SpenderRisky:   rawFlagIsOne(approval.AddressInfo.DoubtList) || len(approval.AddressInfo.Malicious) > 0,
			SpenderTrusted: rawFlagIsOne(approval.AddressInfo.TrustList),
			Amount:         strings.TrimSpace(approval.Amount),
			Unlimited:      unlimited,
			ApprovedAt:     approvedAt,
			Transaction:    strings.ToLower(approval.Transaction),
		})
	}
	return rows, nil
}

func rawFlagIsOne(raw json.RawMessage) bool {
	if len(raw) == 0 {
		return false
	}
	var value any
	return json.Unmarshal(raw, &value) == nil && flagIsOne(value)
}

func boundedJSONInt(raw json.RawMessage, min, max int) (int, bool) {
	value, ok := boundedJSONInt64(raw, int64(min), int64(max))
	return int(value), ok
}

func boundedJSONInt64(raw json.RawMessage, min, max int64) (int64, bool) {
	if len(raw) == 0 {
		return 0, false
	}
	var number json.Number
	if err := json.Unmarshal(raw, &number); err != nil {
		var text string
		if err := json.Unmarshal(raw, &text); err != nil {
			return 0, false
		}
		number = json.Number(text)
	}
	value, err := strconv.ParseInt(number.String(), 10, 64)
	return value, err == nil && value >= min && value <= max
}

func validProviderDecimal(value string) bool {
	value = strings.TrimSpace(value)
	return len(value) > 0 && len(value) <= 128 && decimalPattern.MatchString(value)
}

func boundedDisplayText(value string, maxRunes int) string {
	value = strings.TrimSpace(value)
	clean := make([]rune, 0, len(value))
	for _, r := range value {
		if r < 0x20 || r == 0x7f {
			continue
		}
		clean = append(clean, r)
		if len(clean) == maxRunes {
			break
		}
	}
	return string(clean)
}

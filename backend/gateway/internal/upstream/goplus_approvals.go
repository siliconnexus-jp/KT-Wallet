package upstream

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
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
	if err := validateGoPlusApprovalIdentity(chainID, address); err != nil {
		return nil, errors.New("invalid EVM approval identity")
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

	envelope, err := decodeGoPlusEnvelope(data)
	if err != nil || envelope.Code != 1 {
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "malformed or incomplete provider response"}
	}
	tokens, err := decodeRawJSONArray(envelope.Result, maxGoPlusApprovalRows)
	if err != nil {
		return nil, &Unavailable{Upstream: "goplus-approvals", Message: "malformed or incomplete provider response"}
	}
	rows := make([]TokenApproval, 0)
	seen := make(map[string]struct{})
	seenTokens := make(map[string]struct{})
	maxEvidenceTime := time.Now().Add(24 * time.Hour).Unix()
	for _, token := range tokens {
		tokenIdentity, err := approvalTokenIdentity(token)
		if err != nil {
			return nil, &Unavailable{Upstream: "goplus-approvals", Message: "malformed approval record"}
		}
		if _, duplicate := seenTokens[tokenIdentity]; duplicate {
			return nil, &Unavailable{Upstream: "goplus-approvals", Message: "duplicate approval token"}
		}
		seenTokens[tokenIdentity] = struct{}{}
		parsed, err := parseApprovalToken(token, chainID, maxEvidenceTime)
		if err != nil {
			return nil, &Unavailable{Upstream: "goplus-approvals", Message: "malformed approval record"}
		}
		if len(rows)+len(parsed) > maxGoPlusApprovalRows {
			return nil, &Unavailable{Upstream: "goplus-approvals", Message: "provider returned too many approvals"}
		}
		for _, row := range parsed {
			key := row.TokenAddress + "|" + row.Spender
			if _, duplicate := seen[key]; duplicate {
				return nil, &Unavailable{Upstream: "goplus-approvals", Message: "duplicate approval record"}
			}
			seen[key] = struct{}{}
			rows = append(rows, row)
		}
	}
	return rows, nil
}

func approvalTokenIdentity(raw json.RawMessage) (string, error) {
	fields, err := decodeUniqueJSONObject(raw)
	if err != nil {
		return "", err
	}
	addressRaw, present := fields["token_address"]
	if !present {
		return "", errors.New("missing token address")
	}
	address, err := decodeBoundedString(addressRaw, 42, false)
	if err != nil || !evmAddressPattern.MatchString(address) {
		return "", errors.New("invalid token address")
	}
	return strings.ToLower(address), nil
}

func parseApprovalToken(
	raw json.RawMessage,
	expectedChainID string,
	maxEvidenceTime int64,
) ([]TokenApproval, error) {
	fields, err := decodeExactJSONObject(
		raw,
		"token_address", "chain_id", "token_name", "token_symbol",
		"decimals", "balance", "is_open_source", "malicious_address",
		"malicious_behavior", "approved_list",
	)
	if err != nil || requireJSONFields(
		fields,
		"token_address", "chain_id", "token_name", "token_symbol",
		"decimals", "balance", "is_open_source", "malicious_address",
		"malicious_behavior", "approved_list",
	) != nil {
		return nil, errors.New("invalid approval token schema")
	}
	tokenAddress, err := decodeBoundedString(fields["token_address"], 42, false)
	if err != nil || !evmAddressPattern.MatchString(tokenAddress) {
		return nil, errors.New("invalid token address")
	}
	chainID, err := decodeBoundedString(fields["chain_id"], 20, false)
	if err != nil || chainID != expectedChainID {
		return nil, errors.New("approval response chain mismatch")
	}
	tokenName, err := decodeBoundedString(fields["token_name"], 512, false)
	if err != nil {
		return nil, errors.New("invalid token name")
	}
	tokenSymbol, err := decodeBoundedString(fields["token_symbol"], 256, false)
	if err != nil {
		return nil, errors.New("invalid token symbol")
	}
	// Match the mobile Amount boundary. A provider-controlled scale above 36
	// is not useful for supported ERC-20 assets and can create misleading or
	// pathological UI values even though the revoke calldata itself is zero.
	decimals, err := parseExactJSONInt(fields["decimals"], 0, 36)
	balance, balanceErr := decodeBoundedString(fields["balance"], 128, false)
	if err != nil || balanceErr != nil || !validProviderDecimal(balance) {
		return nil, errors.New("invalid token metadata")
	}
	if _, err := parseBinaryFlag(fields["is_open_source"]); err != nil {
		return nil, errors.New("invalid token open-source flag")
	}
	maliciousAddress, err := parseBinaryFlag(fields["malicious_address"])
	if err != nil {
		return nil, errors.New("invalid token risk flag")
	}
	malicious, err := decodeMaliciousBehaviors(fields["malicious_behavior"])
	if err != nil {
		return nil, err
	}
	approved, err := decodeRawJSONArray(fields["approved_list"], maxGoPlusApprovalRows)
	if err != nil {
		return nil, errors.New("invalid approved list")
	}
	rows := make([]TokenApproval, 0, len(approved))
	for _, approval := range approved {
		row, err := parseApprovalContract(
			approval,
			strings.ToLower(tokenAddress),
			boundedDisplayText(tokenName, 80),
			boundedDisplayText(tokenSymbol, 32),
			decimals,
			strings.TrimSpace(balance),
			maliciousAddress || len(malicious) > 0,
			maxEvidenceTime,
		)
		if err != nil {
			return nil, err
		}
		rows = append(rows, row)
	}
	return rows, nil
}

func parseApprovalContract(
	raw json.RawMessage,
	tokenAddress, tokenName, tokenSymbol string,
	decimals int,
	balance string,
	tokenRisky bool,
	maxEvidenceTime int64,
) (TokenApproval, error) {
	fields, err := decodeExactJSONObject(
		raw,
		"approved_contract", "approved_amount", "approved_time",
		"initial_approval_time", "initial_approval_hash", "hash", "address_info",
	)
	if err != nil || requireJSONFields(
		fields,
		"approved_contract", "approved_amount", "approved_time",
		"initial_approval_time", "initial_approval_hash", "hash", "address_info",
	) != nil {
		return TokenApproval{}, errors.New("invalid approval row schema")
	}
	contract, err := decodeBoundedString(fields["approved_contract"], 42, false)
	if err != nil || !evmAddressPattern.MatchString(contract) {
		return TokenApproval{}, errors.New("invalid spender address")
	}
	amount, err := decodeBoundedString(fields["approved_amount"], 128, false)
	amount = strings.TrimSpace(amount)
	unlimited := strings.EqualFold(amount, "Unlimited")
	if err != nil || (!unlimited && !validProviderDecimal(amount)) {
		return TokenApproval{}, errors.New("invalid approval amount")
	}
	approvedAt, err := parseExactJSONInt64(fields["approved_time"], 0, maxEvidenceTime)
	if err != nil {
		return TokenApproval{}, errors.New("invalid approval time")
	}
	initialAt, err := parseExactJSONInt64(fields["initial_approval_time"], 0, maxEvidenceTime)
	if err != nil || (approvedAt > 0 && initialAt > approvedAt) {
		return TokenApproval{}, errors.New("invalid initial approval time")
	}
	transaction, err := decodeBoundedString(fields["hash"], 66, false)
	if err != nil || (transaction != "" && !txHashPattern.MatchString(transaction)) {
		return TokenApproval{}, errors.New("invalid approval transaction")
	}
	initialHash, err := decodeBoundedString(fields["initial_approval_hash"], 66, false)
	if err != nil || (initialHash != "" && !txHashPattern.MatchString(initialHash)) {
		return TokenApproval{}, errors.New("invalid initial approval transaction")
	}
	info, err := parseApprovalAddressInfo(fields["address_info"], maxEvidenceTime)
	if err != nil {
		return TokenApproval{}, err
	}
	return TokenApproval{
		TokenAddress:   tokenAddress,
		TokenName:      tokenName,
		TokenSymbol:    tokenSymbol,
		Decimals:       decimals,
		Balance:        balance,
		TokenRisky:     tokenRisky,
		Spender:        strings.ToLower(contract),
		SpenderName:    info.name,
		SpenderTag:     info.tag,
		SpenderRisky:   info.risky,
		SpenderTrusted: info.trusted,
		Amount:         amount,
		Unlimited:      unlimited,
		ApprovedAt:     approvedAt,
		Transaction:    strings.ToLower(transaction),
	}, nil
}

type parsedApprovalAddressInfo struct {
	name    string
	tag     string
	risky   bool
	trusted bool
}

func parseApprovalAddressInfo(raw json.RawMessage, maxEvidenceTime int64) (parsedApprovalAddressInfo, error) {
	fields, err := decodeExactJSONObject(
		raw,
		"contract_name", "tag", "creator_address", "is_contract",
		"doubt_list", "malicious_behavior", "deployed_time", "trust_list",
		"is_open_source",
	)
	if err != nil || requireJSONFields(
		fields,
		"contract_name", "tag", "creator_address", "is_contract",
		"doubt_list", "malicious_behavior", "deployed_time", "trust_list",
		"is_open_source",
	) != nil {
		return parsedApprovalAddressInfo{}, errors.New("invalid approval address-info schema")
	}
	name, err := decodeBoundedString(fields["contract_name"], 512, true)
	if err != nil {
		return parsedApprovalAddressInfo{}, err
	}
	tag, err := decodeBoundedString(fields["tag"], 512, true)
	if err != nil {
		return parsedApprovalAddressInfo{}, err
	}
	creator, err := decodeBoundedString(fields["creator_address"], 42, true)
	if err != nil || (creator != "" && !evmAddressPattern.MatchString(creator)) {
		return parsedApprovalAddressInfo{}, errors.New("invalid approval creator address")
	}
	for _, key := range []string{"is_contract", "is_open_source"} {
		if _, err := parseBinaryFlag(fields[key]); err != nil {
			return parsedApprovalAddressInfo{}, errors.New("invalid approval address flag")
		}
	}
	doubt, err := parseBinaryFlag(fields["doubt_list"])
	if err != nil {
		return parsedApprovalAddressInfo{}, errors.New("invalid approval doubt flag")
	}
	trusted, err := parseBinaryFlag(fields["trust_list"])
	if err != nil {
		return parsedApprovalAddressInfo{}, errors.New("invalid approval trust flag")
	}
	malicious, err := decodeMaliciousBehaviors(fields["malicious_behavior"])
	if err != nil {
		return parsedApprovalAddressInfo{}, err
	}
	if !isJSONNull(fields["deployed_time"]) {
		if _, err := parseExactJSONInt64(fields["deployed_time"], 0, maxEvidenceTime); err != nil {
			return parsedApprovalAddressInfo{}, errors.New("invalid approval deployment time")
		}
	}
	return parsedApprovalAddressInfo{
		name:    boundedDisplayText(name, 80),
		tag:     boundedDisplayText(tag, 80),
		risky:   doubt || len(malicious) > 0,
		trusted: trusted,
	}, nil
}

func validProviderDecimal(value string) bool {
	value = strings.TrimSpace(value)
	return len(value) > 0 && len(value) <= 128 && decimalPattern.MatchString(value)
}

func boundedDisplayText(value string, maxRunes int) string {
	value = strings.TrimSpace(value)
	clean := make([]rune, 0, len(value))
	for _, r := range value {
		if r < 0x20 || r == 0x7f || unsafeDisplayRune(r) {
			continue
		}
		clean = append(clean, r)
		if len(clean) == maxRunes {
			break
		}
	}
	return string(clean)
}

func unsafeDisplayRune(r rune) bool {
	return (r >= 0x200b && r <= 0x200f) ||
		(r >= 0x202a && r <= 0x202e) ||
		(r >= 0x2060 && r <= 0x2069) ||
		r == 0xfeff
}

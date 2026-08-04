package upstream

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"math/big"
	"regexp"
	"strings"
)

const (
	solanaBase58Alphabet      = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
	maxSolanaTokenAccountRows = 10000
)

var (
	solanaUnsignedDecimalPattern = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)
	solanaUIAmountPattern        = regexp.MustCompile(`^(0|[1-9][0-9]*)(?:\.[0-9]+)?$`)
	solanaAPIVersionPattern      = regexp.MustCompile(`^[0-9][0-9A-Za-z.+-]{0,31}$`)
	maxSolanaU64                 = new(big.Int).SetUint64(^uint64(0))
)

func isValidSolanaPublicKey(value string) bool {
	if len(value) < 32 || len(value) > 44 {
		return false
	}
	n := new(big.Int)
	base := big.NewInt(58)
	for i := 0; i < len(value); i++ {
		index := strings.IndexByte(solanaBase58Alphabet, value[i])
		if index < 0 {
			return false
		}
		n.Mul(n, base)
		n.Add(n, big.NewInt(int64(index)))
	}
	decoded := n.Bytes()
	leadingZeroes := 0
	for leadingZeroes < len(value) && value[leadingZeroes] == '1' {
		leadingZeroes++
	}
	return leadingZeroes+len(decoded) == 32
}

func parseSolanaU64(raw []byte, quoted bool) (*big.Int, error) {
	value := strings.TrimSpace(string(raw))
	if quoted {
		var decoded string
		if err := json.Unmarshal(raw, &decoded); err != nil {
			return nil, errors.New("invalid Solana unsigned integer")
		}
		value = decoded
	}
	if !solanaUnsignedDecimalPattern.MatchString(value) {
		return nil, errors.New("invalid Solana unsigned integer")
	}
	parsed, ok := new(big.Int).SetString(value, 10)
	if !ok || parsed.Cmp(maxSolanaU64) > 0 {
		return nil, errors.New("out-of-range Solana unsigned integer")
	}
	return parsed, nil
}

func decodeSolanaContext(raw []byte) error {
	contextFields, err := decodeExactJSONObject(raw, "slot", "apiVersion")
	if err != nil {
		return err
	}
	slotRaw, exists := contextFields["slot"]
	if !exists {
		return errors.New("missing Solana context slot")
	}
	if _, err := parseSolanaU64(slotRaw, false); err != nil {
		return err
	}
	if versionRaw, exists := contextFields["apiVersion"]; exists {
		var version string
		if err := json.Unmarshal(versionRaw, &version); err != nil ||
			!solanaAPIVersionPattern.MatchString(version) {
			return errors.New("invalid Solana API version")
		}
	}
	return nil
}

func decodeSolanaNativeBalance(raw []byte) (*big.Int, error) {
	fields, err := decodeExactJSONObject(raw, "context", "value")
	if err != nil {
		return nil, err
	}
	contextRaw, hasContext := fields["context"]
	valueRaw, hasValue := fields["value"]
	if !hasContext || !hasValue {
		return nil, errors.New("incomplete Solana balance result")
	}
	if err := decodeSolanaContext(contextRaw); err != nil {
		return nil, err
	}
	return parseSolanaU64(valueRaw, false)
}

func decodeSolanaTokenBalance(raw []byte, requestedOwner, requestedMint string) (*big.Int, error) {
	fields, err := decodeExactJSONObject(raw, "context", "value")
	if err != nil {
		return nil, err
	}
	contextRaw, hasContext := fields["context"]
	valueRaw, hasValue := fields["value"]
	if !hasContext || !hasValue {
		return nil, errors.New("incomplete Solana token-account result")
	}
	if err := decodeSolanaContext(contextRaw); err != nil {
		return nil, err
	}
	rows, err := decodeRawJSONArray(valueRaw, maxSolanaTokenAccountRows)
	if err != nil {
		return nil, err
	}
	total := new(big.Int)
	seen := make(map[string]struct{}, len(rows))
	for _, rowRaw := range rows {
		row, err := decodeExactJSONObject(rowRaw, "pubkey", "account")
		if err != nil {
			return nil, err
		}
		pubkey, err := requiredSolanaString(row, "pubkey", 44)
		if err != nil || !isValidSolanaPublicKey(pubkey) {
			return nil, errors.New("invalid Solana token-account identity")
		}
		if _, duplicate := seen[pubkey]; duplicate {
			return nil, errors.New("duplicate Solana token-account identity")
		}
		seen[pubkey] = struct{}{}
		accountRaw, exists := row["account"]
		if !exists {
			return nil, errors.New("missing Solana token account")
		}
		amount, err := decodeSolanaTokenAccount(accountRaw, requestedOwner, requestedMint)
		if err != nil {
			return nil, err
		}
		total.Add(total, amount)
		if total.Cmp(maxSolanaU64) > 0 {
			return nil, errors.New("Solana token balance sum exceeds uint64")
		}
	}
	return total, nil
}

func decodeSolanaTokenAccount(raw []byte, requestedOwner, requestedMint string) (*big.Int, error) {
	account, err := decodeExactJSONObject(raw, "data", "executable", "lamports", "owner", "rentEpoch", "space")
	if err != nil {
		return nil, err
	}
	for _, required := range []string{"data", "executable", "lamports", "owner", "rentEpoch"} {
		if _, exists := account[required]; !exists {
			return nil, fmt.Errorf("missing Solana account member %q", required)
		}
	}
	var executable bool
	if err := json.Unmarshal(account["executable"], &executable); err != nil || executable {
		return nil, errors.New("invalid executable Solana token account")
	}
	if _, err := parseSolanaU64(account["lamports"], false); err != nil {
		return nil, err
	}
	if _, err := parseSolanaU64(account["rentEpoch"], false); err != nil {
		return nil, err
	}
	programOwner, err := requiredSolanaString(account, "owner", 44)
	if err != nil || (programOwner != splTokenProgram && programOwner != splToken2022Program) {
		return nil, errors.New("unexpected Solana token program owner")
	}
	accountSpace, err := optionalSolanaSpace(account, "space")
	if err != nil {
		return nil, err
	}

	data, err := decodeExactJSONObject(account["data"], "program", "parsed", "space")
	if err != nil {
		return nil, err
	}
	program, err := requiredSolanaString(data, "program", 32)
	if err != nil || (program != "spl-token" && program != "spl-token-2022") {
		return nil, errors.New("invalid Solana parsed token program")
	}
	if programOwner == splTokenProgram && program != "spl-token" {
		return nil, errors.New("Solana token program identity mismatch")
	}
	dataSpace, err := optionalSolanaSpace(data, "space")
	if err != nil {
		return nil, err
	}
	if accountSpace != nil && dataSpace != nil && accountSpace.Cmp(dataSpace) != 0 {
		return nil, errors.New("Solana token account space mismatch")
	}
	parsedRaw, exists := data["parsed"]
	if !exists {
		return nil, errors.New("missing parsed Solana token account")
	}
	parsed, err := decodeExactJSONObject(parsedRaw, "info", "type")
	if err != nil {
		return nil, err
	}
	parsedType, err := requiredSolanaString(parsed, "type", 32)
	if err != nil || parsedType != "account" {
		return nil, errors.New("unexpected Solana parsed account type")
	}
	infoRaw, exists := parsed["info"]
	if !exists {
		return nil, errors.New("missing Solana token account info")
	}
	return decodeSolanaTokenInfo(infoRaw, requestedOwner, requestedMint)
}

func decodeSolanaTokenInfo(raw []byte, requestedOwner, requestedMint string) (*big.Int, error) {
	info, err := decodeUniqueJSONObject(raw)
	if err != nil {
		return nil, err
	}
	consumed := []string{"isNative", "mint", "owner", "state", "tokenAmount"}
	for key := range info {
		for _, canonical := range consumed {
			if strings.EqualFold(key, canonical) && key != canonical {
				return nil, fmt.Errorf("ambiguous Solana token-info member %q", key)
			}
		}
	}
	for _, required := range consumed {
		if _, exists := info[required]; !exists {
			return nil, fmt.Errorf("missing Solana token-info member %q", required)
		}
	}
	var isNative bool
	if err := json.Unmarshal(info["isNative"], &isNative); err != nil {
		return nil, errors.New("invalid Solana native-token flag")
	}
	_ = isNative // Both wrapped-native and ordinary SPL accounts carry balances.
	mint, err := requiredSolanaString(info, "mint", 44)
	if err != nil || mint != requestedMint || !isValidSolanaPublicKey(mint) {
		return nil, errors.New("Solana token mint identity mismatch")
	}
	owner, err := requiredSolanaString(info, "owner", 44)
	if err != nil || owner != requestedOwner || !isValidSolanaPublicKey(owner) {
		return nil, errors.New("Solana token owner identity mismatch")
	}
	state, err := requiredSolanaString(info, "state", 32)
	if err != nil || (state != "initialized" && state != "frozen") {
		return nil, errors.New("invalid Solana token account state")
	}
	return decodeSolanaTokenAmount(info["tokenAmount"])
}

func decodeSolanaTokenAmount(raw []byte) (*big.Int, error) {
	fields, err := decodeExactJSONObject(raw, "amount", "decimals", "uiAmount", "uiAmountString")
	if err != nil {
		return nil, err
	}
	for _, required := range []string{"amount", "decimals", "uiAmount", "uiAmountString"} {
		if _, exists := fields[required]; !exists {
			return nil, fmt.Errorf("missing Solana token-amount member %q", required)
		}
	}
	amount, err := parseSolanaU64(fields["amount"], true)
	if err != nil {
		return nil, err
	}
	var decimals int
	if err := json.Unmarshal(fields["decimals"], &decimals); err != nil || decimals < 0 || decimals > 255 {
		return nil, errors.New("invalid Solana token decimals")
	}
	uiRaw := bytes.TrimSpace(fields["uiAmount"])
	if !bytes.Equal(uiRaw, []byte("null")) {
		var uiAmount float64
		if err := json.Unmarshal(uiRaw, &uiAmount); err != nil || math.IsNaN(uiAmount) || math.IsInf(uiAmount, 0) || uiAmount < 0 {
			return nil, errors.New("invalid Solana UI amount")
		}
	}
	uiAmountString, err := requiredSolanaString(fields, "uiAmountString", 128)
	if err != nil || !solanaUIAmountPattern.MatchString(uiAmountString) ||
		uiAmountString != canonicalSolanaUIAmount(amount, decimals) {
		return nil, errors.New("inconsistent Solana UI amount string")
	}
	return amount, nil
}

func canonicalSolanaUIAmount(amount *big.Int, decimals int) string {
	digits := amount.String()
	if decimals == 0 {
		return digits
	}
	if len(digits) <= decimals {
		digits = strings.Repeat("0", decimals-len(digits)+1) + digits
	}
	point := len(digits) - decimals
	whole := digits[:point]
	fraction := strings.TrimRight(digits[point:], "0")
	if fraction == "" {
		return whole
	}
	return whole + "." + fraction
}

func requiredSolanaString(fields map[string]json.RawMessage, key string, maximum int) (string, error) {
	raw, exists := fields[key]
	if !exists {
		return "", fmt.Errorf("missing Solana string %q", key)
	}
	var value string
	if err := json.Unmarshal(raw, &value); err != nil || value == "" || len(value) > maximum {
		return "", fmt.Errorf("invalid Solana string %q", key)
	}
	return value, nil
}

func optionalSolanaSpace(fields map[string]json.RawMessage, key string) (*big.Int, error) {
	raw, exists := fields[key]
	if !exists {
		return nil, nil
	}
	return parseSolanaU64(raw, false)
}

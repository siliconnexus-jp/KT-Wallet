package upstream

import (
	"encoding/json"
	"errors"
	"math"
	"math/big"
)

const (
	maxEVMFeeHistoryBlocks     = 1024
	maxEVMFeeRewardPercentiles = 100
)

func validateEVMFeeHistoryRequest(blockCount int, percentiles []float64) error {
	if blockCount <= 0 || blockCount > maxEVMFeeHistoryBlocks ||
		len(percentiles) == 0 || len(percentiles) > maxEVMFeeRewardPercentiles {
		return errors.New("invalid fee history request bounds")
	}
	previous := -1.0
	for _, percentile := range percentiles {
		if math.IsNaN(percentile) || math.IsInf(percentile, 0) ||
			percentile < 0 || percentile > 100 || percentile <= previous {
			return errors.New("invalid fee history reward percentiles")
		}
		previous = percentile
	}
	return nil
}

func decodeEVMFeeHistory(
	raw json.RawMessage,
	requestedBlocks int,
	percentileCount int,
) (*FeeHistoryResult, error) {
	fields, err := decodeExactJSONObject(
		raw,
		"oldestBlock",
		"baseFeePerGas",
		"baseFeePerBlobGas",
		"gasUsedRatio",
		"blobGasUsedRatio",
		"reward",
	)
	if err != nil {
		return nil, err
	}
	for _, required := range []string{"oldestBlock", "baseFeePerGas", "gasUsedRatio"} {
		if _, exists := fields[required]; !exists {
			return nil, errors.New("incomplete fee history result")
		}
	}
	if _, err := parseQuantity(fields["oldestBlock"]); err != nil {
		return nil, errors.New("invalid oldest fee history block")
	}

	gasRatios, err := decodeEVMRatioArray(fields["gasUsedRatio"], requestedBlocks)
	if err != nil {
		return nil, err
	}
	returnedBlocks := len(gasRatios)
	baseFees, err := decodeEVMQuantityArray(fields["baseFeePerGas"], requestedBlocks+1)
	if err != nil || len(baseFees) != returnedBlocks+1 {
		return nil, errors.New("base fee count does not match returned range")
	}

	if blobBaseRaw, exists := fields["baseFeePerBlobGas"]; exists {
		blobBaseFees, err := decodeEVMQuantityArray(blobBaseRaw, requestedBlocks+1)
		if err != nil || len(blobBaseFees) != returnedBlocks+1 {
			return nil, errors.New("blob base fee count does not match returned range")
		}
	}
	if blobRatioRaw, exists := fields["blobGasUsedRatio"]; exists {
		blobRatios, err := decodeEVMRatioArray(blobRatioRaw, requestedBlocks)
		if err != nil || len(blobRatios) != returnedBlocks {
			return nil, errors.New("blob gas ratio count does not match returned range")
		}
	}

	result := &FeeHistoryResult{BaseFeePerGas: baseFees}
	rewardRaw, hasReward := fields["reward"]
	if !hasReward {
		return result, nil
	}
	rewardRows, err := decodeRawJSONArray(rewardRaw, requestedBlocks)
	if err != nil || len(rewardRows) != returnedBlocks {
		return nil, errors.New("reward row count does not match returned range")
	}
	result.Reward = make([][]*big.Int, 0, len(rewardRows))
	for _, rowRaw := range rewardRows {
		row, err := decodeEVMQuantityArray(rowRaw, percentileCount)
		if err != nil || len(row) != percentileCount {
			return nil, errors.New("reward row does not match requested percentiles")
		}
		for i := 1; i < len(row); i++ {
			if row[i-1].Cmp(row[i]) > 0 {
				return nil, errors.New("fee history rewards are not monotonic")
			}
		}
		result.Reward = append(result.Reward, row)
	}
	return result, nil
}

func decodeEVMQuantityArray(raw json.RawMessage, maximum int) ([]*big.Int, error) {
	rows, err := decodeRawJSONArray(raw, maximum)
	if err != nil {
		return nil, err
	}
	values := make([]*big.Int, 0, len(rows))
	for _, row := range rows {
		value, err := parseQuantity(row)
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

func decodeEVMRatioArray(raw json.RawMessage, maximum int) ([]float64, error) {
	rows, err := decodeRawJSONArray(raw, maximum)
	if err != nil {
		return nil, err
	}
	values := make([]float64, 0, len(rows))
	for _, row := range rows {
		var value float64
		if err := json.Unmarshal(row, &value); err != nil {
			return nil, errors.New("invalid fee history gas ratio")
		}
		if math.IsNaN(value) || math.IsInf(value, 0) || value < 0 || value > 1 {
			return nil, errors.New("fee history gas ratio out of range")
		}
		values = append(values, value)
	}
	return values, nil
}

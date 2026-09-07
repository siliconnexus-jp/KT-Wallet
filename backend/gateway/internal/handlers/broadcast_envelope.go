package handlers

// Admission checks only framing and the presence of a signature, not account
// ownership, signature recovery, nonce, balance or execution. The node remains
// authoritative. In particular a framed node rejection must not exhaust the
// long-lived idempotency cache either (see broadcastGuard's eviction policy).
// RLP: https://ethereum.org/developers/docs/data-structures-and-encoding/rlp/
// Type 2: https://eips.ethereum.org/EIPS/eip-1559
type broadcastRLP struct {
	list     bool
	data     []byte
	children []broadcastRLP
}

func validEVMBroadcastEnvelope(raw []byte) bool {
	if len(raw) == 0 {
		return false
	}
	typed := raw[0] < 0x80
	txType := raw[0]
	if typed {
		if txType == 0 {
			return false
		}
		raw = raw[1:]
	}
	budget := 4096
	root, used, ok := readBroadcastRLP(raw, 0, &budget)
	if !ok || used != len(raw) || !root.list {
		return false
	}
	fields := root.children
	// A pooled blob transaction can wrap its signed transaction with sidecars.
	if txType == 3 && len(fields) == 4 && fields[0].list {
		fields = fields[0].children
	}
	if len(fields) < 9 || (!typed && len(fields) != 9) ||
		(txType == 1 && len(fields) != 11) || (txType == 2 && len(fields) != 12) {
		return false
	}
	for _, scalar := range fields[len(fields)-2:] {
		if scalar.list || len(scalar.data) == 0 || len(scalar.data) > 32 || scalar.data[0] == 0 {
			return false
		}
	}
	v := fields[len(fields)-3]
	if v.list || len(v.data) > 32 || (len(v.data) > 0 && v.data[0] == 0) {
		return false
	}
	if typed {
		return len(v.data) == 0 || (len(v.data) == 1 && v.data[0] == 1)
	}
	return len(v.data) > 1 || (len(v.data) == 1 && (v.data[0] == 27 || v.data[0] == 28 || v.data[0] >= 35))
}

// Every length is checked against the remaining input before conversion or
// slicing. Depth/item limits bound work for attacker-controlled nested lists.
func readBroadcastRLP(raw []byte, depth int, budget *int) (broadcastRLP, int, bool) {
	if len(raw) == 0 || depth > 8 || *budget <= 0 {
		return broadcastRLP{}, 0, false
	}
	*budget--
	prefix := raw[0]
	if prefix < 0x80 {
		return broadcastRLP{data: raw[:1]}, 1, true
	}
	isList := prefix >= 0xc0
	base := byte(0x80)
	if isList {
		base = 0xc0
	}
	head, size := 1, int(prefix-base)
	if size > 55 {
		lengthBytes := size - 55
		if len(raw) <= lengthBytes || raw[1] == 0 {
			return broadcastRLP{}, 0, false
		}
		head += lengthBytes
		size = 0
		for _, b := range raw[1:head] {
			if size > len(raw)/256 {
				return broadcastRLP{}, 0, false
			}
			size = size*256 + int(b)
			if size > len(raw) {
				return broadcastRLP{}, 0, false
			}
		}
		if size < 56 {
			return broadcastRLP{}, 0, false
		}
	}
	if size > len(raw)-head {
		return broadcastRLP{}, 0, false
	}
	data := raw[head : head+size]
	if !isList && size == 1 && data[0] < 0x80 {
		return broadcastRLP{}, 0, false
	}
	node := broadcastRLP{list: isList, data: data}
	if isList {
		for len(data) > 0 {
			child, n, ok := readBroadcastRLP(data, depth+1, budget)
			if !ok {
				return broadcastRLP{}, 0, false
			}
			node.children = append(node.children, child)
			data = data[n:]
		}
	}
	return node, head + size, true
}

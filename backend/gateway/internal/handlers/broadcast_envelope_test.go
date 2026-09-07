package handlers

import (
	"encoding/hex"
	"testing"
)

func TestEVMBroadcastEnvelopeAdmission(t *testing.T) {
	for _, valid := range []string{
		"c98001018080801b0101",         // legacy
		"c9800101808080250101",         // EIP-155 legacy
		"01cb01800101808080c0800101",   // EIP-2930
		"02cc0180010101808080c0800101", // EIP-1559
	} {
		raw, _ := hex.DecodeString(valid)
		if !validEVMBroadcastEnvelope(raw) {
			t.Fatalf("valid framing rejected: %s", valid)
		}
		if validEVMBroadcastEnvelope(append(raw, 0)) {
			t.Fatal("trailing bytes accepted")
		}
		for n := 0; n < len(raw); n++ {
			if validEVMBroadcastEnvelope(raw[:n]) {
				t.Fatalf("truncated envelope accepted: %s at %d", valid, n)
			}
		}
	}
	for _, invalid := range []string{
		"0000", "0100", "0200", "03c0", "c0", "ff0102030405060708",
		"02c90180010101808080c0",         // unsigned transaction
		"02cc0180010101808080c0808001",   // missing r
		"02cc0180010101808080c0800001",   // zero r
		"02cc0180010101808080c0020101",   // invalid parity
		"02f80c0180010101808080c0800101", // noncanonical length
		"02cd0180010101808080c080810101", // noncanonical scalar
		"c9800101808080800101",           // unsigned legacy v
	} {
		raw, _ := hex.DecodeString(invalid)
		if validEVMBroadcastEnvelope(raw) {
			t.Fatalf("invalid envelope admitted: %s", invalid)
		}
	}
}

func FuzzEVMBroadcastEnvelopeDoesNotPanic(f *testing.F) {
	for _, seed := range []string{"", "0200", "02cc0180010101808080c0800101", "ff0102030405060708"} {
		raw, _ := hex.DecodeString(seed)
		f.Add(raw)
	}
	f.Fuzz(func(t *testing.T, raw []byte) { validEVMBroadcastEnvelope(raw) })
}

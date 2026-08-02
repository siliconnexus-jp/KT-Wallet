package handlers

import (
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

func TestProviderCircuitOpensAndAllowsOneRecoveryProbe(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	circuit := newProviderCircuit(clk)

	for i := 0; i < externalProviderFailureThreshold; i++ {
		permit, allowed := circuit.allow()
		if !allowed {
			t.Fatalf("failure %d was rejected before threshold", i+1)
		}
		circuit.finish(permit, false, true)
	}
	if snapshot := circuit.snapshot(); !snapshot.Open || snapshot.ProbeInFlight {
		t.Fatalf("circuit did not open after threshold: %+v", snapshot)
	}
	if _, allowed := circuit.allow(); allowed {
		t.Fatal("open circuit admitted a request before its recovery window")
	}
	if got := circuit.snapshot().ShortCircuits; got != 1 {
		t.Fatalf("short circuits = %d, want 1", got)
	}

	clk.Advance(externalProviderOpenDuration + time.Second)
	probe, allowed := circuit.allow()
	if !allowed || !probe.probe {
		t.Fatal("expired circuit did not admit a half-open probe")
	}
	if _, allowed := circuit.allow(); allowed {
		t.Fatal("half-open circuit admitted more than one concurrent probe")
	}
	circuit.finish(probe, true, true)
	if snapshot := circuit.snapshot(); snapshot.Open || snapshot.ProbeInFlight {
		t.Fatalf("successful probe did not close circuit: %+v", snapshot)
	}
}

func TestProviderCircuitFailedProbeReopensFullWindow(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	circuit := newProviderCircuit(clk)
	for range externalProviderFailureThreshold {
		permit, _ := circuit.allow()
		circuit.finish(permit, false, true)
	}
	clk.Advance(externalProviderOpenDuration + time.Second)
	probe, allowed := circuit.allow()
	if !allowed {
		t.Fatal("expected half-open probe")
	}
	circuit.finish(probe, false, true)
	clk.Advance(externalProviderOpenDuration - time.Second)
	if _, allowed := circuit.allow(); allowed {
		t.Fatal("failed probe did not reopen the full circuit window")
	}
}

func TestProviderCircuitIgnoresCallerCancellation(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	circuit := newProviderCircuit(clk)
	for range externalProviderFailureThreshold + 2 {
		permit, allowed := circuit.allow()
		if !allowed {
			t.Fatal("caller cancellation unexpectedly opened circuit")
		}
		circuit.finish(permit, false, false)
	}
	if snapshot := circuit.snapshot(); snapshot.Open {
		t.Fatalf("caller cancellation changed provider health: %+v", snapshot)
	}
}

func TestProviderCircuitStaleSuccessCannotCloseNewerFailureCircuit(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	circuit := newProviderCircuit(clk)
	permits := make([]providerPermit, externalProviderFailureThreshold+1)
	for i := range permits {
		permit, allowed := circuit.allow()
		if !allowed {
			t.Fatalf("parallel request %d unexpectedly rejected", i)
		}
		permits[i] = permit
	}
	for i := 0; i < externalProviderFailureThreshold; i++ {
		circuit.finish(permits[i], false, true)
	}
	circuit.finish(permits[len(permits)-1], true, true)
	if snapshot := circuit.snapshot(); !snapshot.Open {
		t.Fatalf("stale success closed newer failure circuit: %+v", snapshot)
	}
}

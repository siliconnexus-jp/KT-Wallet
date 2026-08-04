# Security Provider Incident Runbook

This runbook covers the external GoPlus Token Security, Solana Token Security,
and opt-in EVM Token Approval services. It does not make these providers a
source of truth: the operator's exact `network + contract/mint` denylist still
wins, and provider failure must remain `unknown/unavailable`, never `safe` or
an empty approval list.

## Signals and privacy boundary

Use only the fixed-label Prometheus series:

- `kt_gateway_token_risk_provider_operations_total`
- `kt_gateway_token_approval_provider_operations_total`
- `kt_gateway_external_provider_circuit_open`
- `kt_gateway_external_provider_circuit_probe_inflight`
- `kt_gateway_external_provider_circuit_short_circuits_total`

The three circuit labels are fixed to `token_risk_evm`,
`token_risk_solana`, and `token_approvals_evm`. Never add an address, contract,
provider URL, API key, request body, or response text as a metric label or log
field.

Each provider circuit opens after three consecutive failures, rejects further
calls for 30 seconds, and then admits exactly one half-open recovery probe.
Caller cancellation does not count as a provider failure. A successful probe
closes the circuit; a failed probe opens a new full window. Risk and approval
caches never turn an error into a new safe/empty response.

## Triage

1. Confirm both Gateway targets are up and the affected circuit label is
   actually open. Do not infer provider failure from a client screenshot.
2. Compare provider error counters with Gateway JSON-RPC endpoint health. A
   chain RPC outage and a security-provider outage have different controls.
3. Run `sh ops/verify-token-risk-matrix.sh https://gateway.example` from the
   Gateway source directory. It checks one official public identity on all
   eight supported mainnets and fails on any unavailable, unknown, unsafe,
   malformed, oversized or non-provider-backed result. Never use a customer
   wallet address for risk or approval diagnostics.
4. Check the provider's published status and API version from an operator
   workstation. Do not paste provider credentials into tickets or chat.
5. If the response schema changed, capture a sanitized structural fixture with
   all addresses and free-form provider text removed, then reproduce in the
   deterministic test harness before changing the parser. Do not restore a
   permissive struct/map `json.Unmarshal`: envelope/result identity, EVM
   decisive flags, Solana `creators` plus all privileged authority fields, and
   Approval `chain_id` plus its three nested schemas must stay independently
   bound and duplicate-free.

## Containment and rollback

- Suspected false negative or malicious identity: add the exact identity to
  `TOKEN_RISKS_FILE`, validate startup, deploy through the candidate port, and
  verify `source=operator_registry`. This emergency override takes precedence
  over both the official catalog and provider.
- Repeated provider outage: set `DISABLE_EXTERNAL_TOKEN_RISK=true` and/or
  `DISABLE_EXTERNAL_APPROVAL_LOOKUP=true` in the protected EnvironmentFile,
  roll instances one at a time, and verify clients show unavailable/unknown or
  unsupported. Never substitute an empty success payload.
- Parser or behavior regression introduced by a Gateway release: atomically
  restore the previous release symlink and restart secondary then primary.
  Keep the old release and monitoring rules until the new version has passed
  candidate-port, dual-instance, and public read-only smoke tests.
- Do not remove an exact risk override during the incident. Removal requires a
  second reviewer and independent evidence that the full contract/mint identity
  is no longer unsafe.

## Recovery gate

Recovery is complete only when all of the following are true:

1. The affected provider returns a schema accepted by current production code;
   a quota/error envelope missing `result` is not a successful schema sample.
2. The eight-mainnet read-only matrix returns 8/8 provider-backed safe results,
   and the deterministic unsafe/error/malformed fixtures remain rejected by
   `make token-risk-matrix-test`.
3. The half-open probe closes the circuit on both Gateway instances.
4. Error and short-circuit counters stop increasing for at least 15 minutes.
5. No mobile path displays a green safe result or empty approval list for an
   injected timeout, 429, 5xx, redirect, oversized body, or malformed response.
6. Prometheus rules pass `promtool check rules`, both targets are up, and the
   public unauthenticated metrics endpoint still returns 404.

Long-term provider SLA, notification delivery, and user false-positive intake
remain operational requirements. This runbook and its automated circuit tests
do not prove those external processes are staffed or effective.

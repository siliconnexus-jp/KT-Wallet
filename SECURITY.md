# Security Policy

KT Wallet is self-custody software. A vulnerability can put recovery phrases,
private keys, signatures, or transaction intent at risk. Please report security
issues privately and do not include secrets in any report.

## Private reporting

Use GitHub's private vulnerability reporting form:

https://github.com/siliconnexus-jp/KT-Wallet/security/advisories/new

Do not open a public issue for a suspected vulnerability. If the private form
is unavailable, open a public issue containing only the words "private security
contact requested". Do not include reproduction steps, affected addresses,
logs, screenshots, keys, recovery phrases, transaction payloads, provider
credentials, or other sensitive details. A maintainer will arrange a private
channel.

KT Wallet will never ask a reporter to send a recovery phrase or private key.
Use a new test wallet with no valuable assets when a proof of concept requires
signing or broadcasting.

## Response targets

These are operational targets for the public-test phase, not a warranty:

- acknowledgement within 3 business days;
- initial severity and scope assessment within 7 business days;
- a status update at least every 14 calendar days while the report is open;
- coordinated disclosure only after a fix or documented mitigation is
  available to affected users.

Critical reports involving private-key disclosure, signing without explicit
authentication, transaction-content substitution, signature forgery, remote
code execution, or bypass of offline-signing policy are handled first. Release
timing depends on reproducibility, affected platforms, upstream dependencies,
and safe migration requirements.

## In scope

- KT Wallet and KT Cold Signer production routes for iOS and Android;
- native key storage, derivation, authentication, and signing in `core_crypto`;
- air-gapped QR encoding, parsing, replay protection, and online verification;
- transaction construction, simulation, confirmation, broadcast, and Pending
  state handling;
- the optional KT Gateway where a defect can change wallet security decisions,
  leak wallet data, or expose provider credentials;
- release artifacts published by the `siliconnexus-jp/KT-Wallet` project.

## Usually out of scope

- denial of service against public testnets, faucets, explorers, or third-party
  RPC providers;
- attacks that require a previously rooted/jailbroken or malware-controlled
  device, unless KT Wallet incorrectly reports that device as safe;
- social engineering, seed phrases that a user voluntarily disclosed, and
  losses caused only by sending to the wrong correctly displayed address;
- findings that depend on demo/gallery/test-only routes and cannot reach a
  production build;
- automated scanner output without a reproducible security impact.

These exclusions do not prevent reporting a credible chain of impact. Explain
the practical effect and the production path that is affected.

## A useful report contains

- affected app, platform, version/commit, network, and wallet mode;
- a concise impact statement and prerequisites;
- minimal reproducible steps using a disposable test wallet;
- expected and observed behavior;
- sanitized logs or screenshots with addresses and identifiers redacted;
- suggested remediation, if known.

## Disclosure and safe research

Give maintainers a reasonable opportunity to investigate and ship a fix before
public disclosure. Do not access other users' data, disrupt services, test with
valuable mainnet assets, or retain secrets encountered accidentally. Good-faith
research that follows this policy will not be pursued by the project solely for
the act of testing and reporting.

This policy does not claim that KT Wallet has completed an independent security
audit. See [Security and Risk](SECURITY_AND_RISK.md) for the current trust and
usage limitations.

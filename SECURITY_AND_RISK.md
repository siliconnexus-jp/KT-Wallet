# Security and Risk Notice

KT Wallet is experimental open-source self-custody software. Users control the
keys and bear the risk of loss. There is no password-reset service and no party
can recover a deleted key or an unrecorded recovery phrase.

Before signing, verify the network, destination, raw amount, token contract and
maximum fee on the offline device. A QR summary is not trusted; production
signing accepts only supported transaction encodings parsed from the raw
transaction.

Public RPC nodes, explorers, token contracts and testnet faucets are external
services. They can be unavailable, rate-limited, incorrect or malicious. A
successful signature or RPC submission is not the same as on-chain
confirmation. KT Wallet records these stages separately.

Rooted or jailbroken devices, active screen sharing, malware, an exposed
recovery phrase and unverified application builds can compromise funds.
Security checks can return “unknown”; unknown is never displayed as a passed
check. Use the standalone Cold Signer on a dedicated, permanently offline
device for stronger isolation.

Never treat testnet assets as valuable and never send mainnet funds while
evaluating this project.

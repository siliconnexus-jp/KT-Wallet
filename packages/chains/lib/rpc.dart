/// RPC clients for the ONLINE app only (KT Wallet). The offline signer must
/// never import this entrypoint — enforced by the dependency firewall
/// (tech-plan.md §4, tool/check_deps.dart bans `package:chains/rpc`).
library;

export 'src/rpc/evm_rpc.dart';
export 'src/rpc/solana_rpc.dart';
export 'src/rpc/transport.dart';
export 'src/rpc/tron_rpc.dart';

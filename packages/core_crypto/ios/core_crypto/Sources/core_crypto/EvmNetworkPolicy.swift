import Foundation

enum EvmNetworkPolicy {
  private static let domains: [UInt64: String] = [
    1: "eth", 11155111: "eth", 137: "polygon", 80002: "polygon",
    8453: "base", 84532: "base", 42161: "arbitrum", 421614: "arbitrum",
    43114: "avalanche", 43113: "avalanche", 56: "bnb", 97: "bnb",
  ]
  static func allows(coin: String, raw: Data, allowUnknown: Bool) -> Bool {
    let significant = raw.drop(while: { $0 == 0 })
    guard !significant.isEmpty else { return false }
    guard significant.count <= 8 else { return allowUnknown }
    let id = significant.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    guard let expected = domains[id] else { return allowUnknown }
    return expected == coin
  }
}

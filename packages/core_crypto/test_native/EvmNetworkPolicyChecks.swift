import Foundation

@main
enum EvmNetworkPolicyChecks {
  static func main() {
    let pairs: [UInt64: String] = [
      1: "eth", 11155111: "eth", 137: "polygon", 80002: "polygon",
      8453: "base", 84532: "base", 42161: "arbitrum", 421614: "arbitrum",
      43114: "avalanche", 43113: "avalanche", 56: "bnb", 97: "bnb",
    ]
    for (id, expected) in pairs {
      var bytes = id.bigEndian
      let data = withUnsafeBytes(of: &bytes) { Data($0) }
      for coin in Set(pairs.values) {
        precondition(EvmNetworkPolicy.allows(coin: coin, raw: data, allowUnknown: false) == (coin == expected))
      }
    }
    precondition(!EvmNetworkPolicy.allows(coin: "bnb", raw: Data([1]), allowUnknown: true))
    precondition(!EvmNetworkPolicy.allows(coin: "eth", raw: Data([127]), allowUnknown: false))
    precondition(EvmNetworkPolicy.allows(coin: "eth", raw: Data([127]), allowUnknown: true))
    precondition(!EvmNetworkPolicy.allows(coin: "eth", raw: Data(), allowUnknown: true))
    precondition(!EvmNetworkPolicy.allows(coin: "eth", raw: Data([0]), allowUnknown: true))
    print("EVM native network policy: 72 known-domain combinations and 5 edge cases passed")
  }
}

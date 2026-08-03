#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
guard="$root/ops/verify-token-risk-matrix.sh"
catalog="$root/config/official-tokens.json"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/kt-token-risk-matrix-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

fake_curl="$scratch/curl"
cat > "$fake_curl" <<'EOF'
#!/bin/sh
set -eu
payload=
output=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data-binary)
      payload=$2
      shift 2
      ;;
    --output)
      output=$2
      shift 2
      ;;
    *) shift ;;
  esac
done

id=$(printf '%s' "$payload" | jq -r '.id')
network=$(printf '%s' "$payload" | jq -r '.params.network')
contract=$(printf '%s' "$payload" | jq -r '.params.contract')
case "${FAKE_RISK_MODE:-safe}:$network" in
  transport:eth-mainnet)
    exit 7
    ;;
  unknown:polygon-mainnet)
    jq -cn --arg id "$id" --arg network "$network" --arg contract "$contract" '{jsonrpc:"2.0",id:$id,result:{status:"unknown",source:"goplus",network:$network,contract:$contract}}' > "$output"
    ;;
  unsafe:bnb-mainnet)
    jq -cn --arg id "$id" --arg network "$network" --arg contract "$contract" '{jsonrpc:"2.0",id:$id,result:{status:"unsafe",source:"goplus",category:"honeypot",network:$network,contract:$contract}}' > "$output"
    ;;
  error:base-mainnet)
    jq -cn --arg id "$id" '{jsonrpc:"2.0",id:$id,error:{code:-32002,message:"upstream unavailable"}}' > "$output"
    ;;
  malformed:sol-mainnet)
    printf '{not-json' > "$output"
    ;;
  oversized:sol-mainnet)
    dd if=/dev/zero bs=65537 count=1 2>/dev/null | tr '\000' x > "$output"
    ;;
  catalog-only:eth-mainnet)
    jq -cn --arg id "$id" --arg network "$network" --arg contract "$contract" '{jsonrpc:"2.0",id:$id,result:{status:"safe",source:"official_catalog",network:$network,contract:$contract}}' > "$output"
    ;;
  wrong-id:avalanche-mainnet)
    jq -cn --arg network "$network" --arg contract "$contract" '{jsonrpc:"2.0",id:"different-request",result:{status:"safe",source:"official_catalog+goplus",network:$network,contract:$contract}}' > "$output"
    ;;
  wrong-network:eth-mainnet)
    jq -cn --arg id "$id" --arg contract "$contract" '{jsonrpc:"2.0",id:$id,result:{status:"safe",source:"official_catalog+goplus",network:"polygon-mainnet",contract:$contract}}' > "$output"
    ;;
  wrong-contract:eth-mainnet)
    jq -cn --arg id "$id" --arg network "$network" '{jsonrpc:"2.0",id:$id,result:{status:"safe",source:"official_catalog+goplus",network:$network,contract:"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}' > "$output"
    ;;
  *)
    jq -cn --arg id "$id" --arg network "$network" --arg contract "$contract" '{jsonrpc:"2.0",id:$id,result:{status:"safe",source:"official_catalog+goplus",network:$network,contract:$contract}}' > "$output"
    ;;
esac
EOF
chmod 700 "$fake_curl"

CURL_BIN="$fake_curl" sh "$guard" http://127.0.0.1:8119 "$catalog" > "$scratch/pass.log"
grep -Fq 'token risk matrix: OK (8/8)' "$scratch/pass.log"

for mode in transport unknown unsafe error malformed oversized catalog-only wrong-id wrong-network wrong-contract; do
  if FAKE_RISK_MODE=$mode CURL_BIN="$fake_curl" \
    sh "$guard" http://127.0.0.1:8119 "$catalog" >/dev/null 2>&1; then
    echo "token risk matrix tests: $mode result was accepted" >&2
    exit 1
  fi
done

for endpoint in \
  http://gateway.example \
  'https://user@gateway.example' \
  'https://gateway.example?token=secret' \
  'https://gateway.example#fragment'; do
  if CURL_BIN="$fake_curl" sh "$guard" "$endpoint" "$catalog" >/dev/null 2>&1; then
    echo "token risk matrix tests: unsafe endpoint was accepted: $endpoint" >&2
    exit 1
  fi
done

jq 'map(select(.network != "sol-mainnet"))' "$catalog" > "$scratch/incomplete.json"
if CURL_BIN="$fake_curl" \
  sh "$guard" http://127.0.0.1:8119 "$scratch/incomplete.json" >/dev/null 2>&1; then
  echo "token risk matrix tests: incomplete official catalog was accepted" >&2
  exit 1
fi

echo "token risk matrix tests: OK"

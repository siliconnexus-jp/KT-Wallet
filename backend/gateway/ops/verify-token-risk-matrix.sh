#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
base_url=${1:-}
catalog=${2:-"$root/config/official-tokens.json"}
curl_bin=${CURL_BIN:-curl}

if [ -z "$base_url" ]; then
  echo "usage: $0 https://gateway.example [official-tokens.json]" >&2
  exit 2
fi

case "$base_url" in
  *'@'*|*'?'*|*'#'*)
    echo "token risk matrix: endpoint must not contain credentials, query, or fragment" >&2
    exit 2
    ;;
esac

case "$base_url" in
  https://*) curl_proto='=https' ;;
  http://127.0.0.1|http://127.0.0.1:*|http://localhost|http://localhost:*|http://\[::1\]|http://\[::1\]:*)
    curl_proto='=http'
    ;;
  *)
    echo "token risk matrix: public endpoints must use HTTPS; HTTP is loopback-only" >&2
    exit 2
    ;;
esac

base_url=${base_url%/}
if [ ! -f "$catalog" ]; then
  echo "token risk matrix: missing official token catalog: $catalog" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "token risk matrix: jq is required" >&2
  exit 2
fi
if ! command -v "$curl_bin" >/dev/null 2>&1; then
  echo "token risk matrix: curl executable is unavailable: $curl_bin" >&2
  exit 2
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/kt-token-risk-matrix.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
matrix="$scratch/matrix.tsv"
response="$scratch/response.json"

jq -r '
  [ .[]
    | select(.popular == true)
    | select(.network == "eth-mainnet"
        or .network == "polygon-mainnet"
        or .network == "base-mainnet"
        or .network == "arbitrum-mainnet"
        or .network == "avalanche-mainnet"
        or .network == "bnb-mainnet"
        or .network == "tron-mainnet"
        or .network == "sol-mainnet")
  ]
  | sort_by(.network, .symbol)
  | group_by(.network)
  | map(.[0])
  | .[]
  | [.network, .contract]
  | @tsv
' "$catalog" > "$matrix"

row_count=$(wc -l < "$matrix" | tr -d ' ')
if [ "$row_count" -ne 8 ]; then
  echo "token risk matrix: expected exactly one official sample for each of 8 mainnets; got $row_count" >&2
  exit 1
fi

passed=0
while IFS="$(printf '\t')" read -r network contract; do
  case "$network" in
    eth-mainnet) chain=eth ;;
    polygon-mainnet) chain=polygon ;;
    base-mainnet) chain=base ;;
    arbitrum-mainnet) chain=arbitrum ;;
    avalanche-mainnet) chain=avalanche ;;
    bnb-mainnet) chain=bnb ;;
    tron-mainnet) chain=tron ;;
    sol-mainnet) chain=solana ;;
    *)
      echo "token risk matrix: unexpected network in selected catalog: $network" >&2
      exit 1
      ;;
  esac

  request_id="risk-matrix-$network"
  payload=$(jq -cn \
    --arg id "$request_id" \
    --arg chain "$chain" \
    --arg network "$network" \
    --arg contract "$contract" \
    '{jsonrpc:"2.0",id:$id,method:"kt_checkTokenRisk",params:{chain:$chain,network:$network,contract:$contract}}')

  rm -f "$response"
  if ! "$curl_bin" \
    --silent --show-error --fail \
    --proto "$curl_proto" \
    --connect-timeout 5 --max-time 20 --max-filesize 65536 \
    --request POST \
    --header 'Content-Type: application/json' \
    --data-binary "$payload" \
    --output "$response" \
    "$base_url/rpc"; then
    echo "token risk matrix: request failed for $network" >&2
    exit 1
  fi

  response_size=$(wc -c < "$response" | tr -d ' ')
  if [ "$response_size" -gt 65536 ]; then
    echo "token risk matrix: oversized response for $network" >&2
    exit 1
  fi
  if ! jq -e \
    --arg id "$request_id" \
    --arg chain "$chain" \
    --arg network "$network" \
    --arg contract "$contract" '
      .jsonrpc == "2.0"
      and .id == $id
      and (.error == null)
      and .result.status == "safe"
      and .result.source == "official_catalog+goplus"
      and .result.network == $network
      and (.result.contract | type) == "string"
      and (if ($chain == "tron" or $chain == "solana")
        then .result.contract == $contract
        else (.result.contract | ascii_downcase) == ($contract | ascii_downcase)
        end)
    ' "$response" >/dev/null; then
    echo "token risk matrix: $network did not return identity-bound provider evidence" >&2
    exit 1
  fi

  printf '%s\t%s\t%s\n' "$network" safe official_catalog+goplus
  passed=$((passed + 1))
done < "$matrix"

if [ "$passed" -ne 8 ]; then
  echo "token risk matrix: incomplete result: $passed/8" >&2
  exit 1
fi

echo "token risk matrix: OK (8/8)"

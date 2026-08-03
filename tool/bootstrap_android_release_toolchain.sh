#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$repo_root/tool/android-release-toolchain.lock"
wallet_metadata="$repo_root/apps/kt_wallet/android/gradle/verification-metadata.xml"
signer_metadata="$repo_root/apps/cold_signer/android/gradle/verification-metadata.xml"
wallet_settings="$repo_root/apps/kt_wallet/android/settings.gradle.kts"
cache_dir="${KT_ANDROID_RELEASE_TOOLCHAIN_CACHE:-$repo_root/.dart_tool/android-release-toolchain}"

for command_name in curl shasum unzip xmllint; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required to bootstrap the Android release toolchain" >&2
    exit 2
  fi
done
for required_file in "$lock_file" "$wallet_metadata" "$signer_metadata" "$wallet_settings"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Android release toolchain input is unavailable: $required_file" >&2
    exit 2
  fi
done

bundletool_version="$(sed -n 's/^bundletool\.version=\(.*\)$/\1/p' "$lock_file")"
bundletool_sha="$(sed -n 's/^bundletool\.sha256=\([0-9a-f]\{64\}\)$/\1/p' "$lock_file")"
if [[ -z "$bundletool_version" || -z "$bundletool_sha" ]]; then
  echo "Android release toolchain lock is malformed" >&2
  exit 2
fi

mkdir -p "$cache_dir"
temp_dir="$(mktemp -d "$cache_dir/.bootstrap.XXXXXX")"
cleanup() { rm -rf "$temp_dir"; }
trap cleanup EXIT

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

download_checked() {
  local url="$1"
  local destination="$2"
  local expected_sha="$3"
  local name
  name="$(basename "$destination")"
  if [[ -f "$destination" && "$(sha256 "$destination")" == "$expected_sha" ]]; then
    echo "OK: cached $name"
    return
  fi
  local staged="$temp_dir/$name"
  curl --fail --show-error --silent --location \
    --proto '=https' --proto-redir '=https' --max-redirs 3 --tlsv1.2 \
    "$url" --output "$staged"
  if [[ "$(sha256 "$staged")" != "$expected_sha" ]]; then
    echo "Downloaded Android release dependency failed SHA-256: $name" >&2
    exit 2
  fi
  mv -f "$staged" "$destination"
  echo "OK: downloaded and verified $name"
}

bundletool_name="bundletool-$bundletool_version.jar"
bundletool_path="$cache_dir/$bundletool_name"
download_checked \
  "https://dl.google.com/dl/android/maven2/com/android/tools/build/bundletool/$bundletool_version/$bundletool_name" \
  "$bundletool_path" "$bundletool_sha"

dependency_names="$(
  unzip -p "$bundletool_path" META-INF/MANIFEST.MF | tr -d '\r' |
    awk 'BEGIN { active=0 }
      /^Class-Path:/ {
        active=1
        sub(/^Class-Path: /, "")
        printf "%s", $0
        next
      }
      active && /^ / {
        sub(/^ /, "")
        printf "%s", $0
        next
      }
      active { exit }
      END { print "" }'
)"

agp_version="$(
  sed -n 's/.*id("com\.android\.application") version "\([^"]*\)".*/\1/p' \
    "$wallet_settings" | head -n 1
)"
if [[ -z "$agp_version" ]]; then
  echo "Android Gradle Plugin version is unavailable" >&2
  exit 2
fi
aapt2_name="$(xmllint --xpath \
  "string((//*[local-name()='component'][@group='com.android.tools.build' and @name='aapt2-proto' and starts-with(@version, '$agp_version-')]/*[local-name()='artifact'][contains(@name, '.jar')])[1]/@name)" \
  "$wallet_metadata")"
if [[ -z "$aapt2_name" ]]; then
  echo "AGP-matched aapt2-proto is absent from verification metadata" >&2
  exit 2
fi

for manifest_name in $dependency_names; do
  artifact_name="$manifest_name"
  if [[ "$manifest_name" == aapt2-proto-*.jar ]]; then
    artifact_name="$aapt2_name"
  fi

  xpath_component="(//*[local-name()='component'][*[local-name()='artifact'][@name='$artifact_name']])[1]"
  wallet_group="$(xmllint --xpath "string($xpath_component/@group)" "$wallet_metadata")"
  wallet_module="$(xmllint --xpath "string($xpath_component/@name)" "$wallet_metadata")"
  wallet_version="$(xmllint --xpath "string($xpath_component/@version)" "$wallet_metadata")"
  wallet_sha="$(xmllint --xpath \
    "string(($xpath_component/*[local-name()='artifact'][@name='$artifact_name']/*[local-name()='sha256'])[1]/@value)" \
    "$wallet_metadata")"
  signer_group="$(xmllint --xpath "string($xpath_component/@group)" "$signer_metadata")"
  signer_module="$(xmllint --xpath "string($xpath_component/@name)" "$signer_metadata")"
  signer_version="$(xmllint --xpath "string($xpath_component/@version)" "$signer_metadata")"
  signer_sha="$(xmllint --xpath \
    "string(($xpath_component/*[local-name()='artifact'][@name='$artifact_name']/*[local-name()='sha256'])[1]/@value)" \
    "$signer_metadata")"

  if [[ -z "$wallet_group" || -z "$wallet_module" || -z "$wallet_version" ||
    ! "$wallet_sha" =~ ^[0-9a-f]{64}$ ||
    "$wallet_group" != "$signer_group" ||
    "$wallet_module" != "$signer_module" ||
    "$wallet_version" != "$signer_version" ||
    "$wallet_sha" != "$signer_sha" ]]; then
    echo "Android release dependency metadata mismatch: $artifact_name" >&2
    exit 2
  fi

  group_path="$(printf '%s' "$wallet_group" | tr '.' '/')"
  if [[ "$wallet_group" == com.android.tools* ]]; then
    repository="https://dl.google.com/dl/android/maven2"
  else
    repository="https://repo.maven.apache.org/maven2"
  fi
  download_checked \
    "$repository/$group_path/$wallet_module/$wallet_version/$artifact_name" \
    "$cache_dir/$artifact_name" "$wallet_sha"
done

echo "Android release toolchain bootstrap passed: $cache_dir"

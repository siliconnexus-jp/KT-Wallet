#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
interop_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kt-portable-backup.XXXXXX")
trap 'rm -rf -- "$interop_tmp_dir"' EXIT HUP INT TERM

xcrun swiftc \
  "$repo_root/packages/core_crypto/ios/core_crypto/Sources/core_crypto/PortableBackupCipher.swift" \
  "$repo_root/tool/portable_backup_vector/main.swift" \
  -o "$interop_tmp_dir/portable-backup-vector"

"$interop_tmp_dir/portable-backup-vector"

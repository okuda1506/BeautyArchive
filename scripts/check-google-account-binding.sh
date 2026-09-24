#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/bone-google-account.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT

swiftc -swift-version 5 \
  -module-cache-path "$check_dir/module-cache" \
  "$project_dir/BeautyArchive/GoogleOAuthCore.swift" \
  "$project_dir/BeautyArchive/GoogleCredentialStore.swift" \
  "$project_dir/scripts/GoogleAccountBindingContract.swift" \
  -o "$check_dir/check-google-account-binding"
"$check_dir/check-google-account-binding"

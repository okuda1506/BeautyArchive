#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/bone-form-ux.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT

swiftc -swift-version 5 \
  -module-cache-path "$check_dir/module-cache" \
  "$project_dir/BeautyArchive/JapanesePresentation.swift" \
  "$project_dir/BeautyArchive/FormDraftState.swift" \
  "$project_dir/scripts/FormUXContract.swift" \
  -o "$check_dir/check-form-ux"
"$check_dir/check-form-ux"

#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/bone-launch-presentation.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT

swiftc -swift-version 5 \
  -module-cache-path "$check_dir/module-cache" \
  "$project_dir/BeautyArchive/LaunchPresentation.swift" \
  "$project_dir/scripts/LaunchPresentationContract.swift" \
  -o "$check_dir/check-launch-presentation"
"$check_dir/check-launch-presentation"

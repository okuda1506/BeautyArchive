#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/bone-google-writer.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT

swiftc -swift-version 5 \
  -module-cache-path "$check_dir/module-cache" \
  "$project_dir/BeautyArchive/GoogleCalendarWriter.swift" \
  "$project_dir/scripts/GoogleCalendarWriterContract.swift" \
  -o "$check_dir/check-google-calendar-writer"
"$check_dir/check-google-calendar-writer"

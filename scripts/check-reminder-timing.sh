#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/bone-reminder-timing.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT

swiftc -swift-version 5 \
  -module-cache-path "$check_dir/module-cache" \
  "$project_dir/BeautyArchive/ReminderPreferences.swift" \
  "$project_dir/BeautyArchive/ReminderTimingSnapshot.swift" \
  "$project_dir/BeautyArchive/ReminderTimingSettings.swift" \
  "$project_dir/scripts/ReminderTimingContract.swift" \
  -o "$check_dir/check-reminder-timing"
"$check_dir/check-reminder-timing"

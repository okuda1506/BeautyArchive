#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/bone-notification-actions.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT

swiftc -swift-version 5 \
  -module-cache-path "$check_dir/module-cache" \
  "$project_dir/BeautyArchive/ReminderPreferences.swift" \
  "$project_dir/BeautyArchive/BeautyProduct.swift" \
  "$project_dir/BeautyArchive/ProductUnit.swift" \
  "$project_dir/BeautyArchive/ProductPurchasePlan.swift" \
  "$project_dir/BeautyArchive/ReplacementEstimate.swift" \
  "$project_dir/BeautyArchive/SalonRecord.swift" \
  "$project_dir/BeautyArchive/SalonPhoto.swift" \
  "$project_dir/BeautyArchive/BeautyAppointment.swift" \
  "$project_dir/BeautyArchive/SalonReminderAdjustment.swift" \
  "$project_dir/BeautyArchive/HomeAction.swift" \
  "$project_dir/BeautyArchive/ProductNotificationScheduler.swift" \
  "$project_dir/BeautyArchive/SalonNotificationScheduler.swift" \
  "$project_dir/BeautyArchive/LocalNotificationReconciler.swift" \
  "$project_dir/BeautyArchive/ReminderNotificationTarget.swift" \
  "$project_dir/BeautyArchive/ReminderNotificationSnoozeStore.swift" \
  "$project_dir/BeautyArchive/ReminderNotificationCoordinator.swift" \
  "$project_dir/scripts/ReminderNotificationActionsContract.swift" \
  -o "$check_dir/check-reminder-notification-actions"
"$check_dir/check-reminder-notification-actions"

# Beauty Archive

[日本語](README.ja.md)

## Overview

Beauty Archive is an iOS app for keeping beauty records, schedules, and next actions together. Development is at an early stage; the current app is a SwiftUI starter screen, and the features below describe the planned initial release. Requirements may change as the project develops.

## Purpose

Help people recall their previous salon visits, prepare for the next appointment, and keep track of when to book a treatment or replace a product. The app is intended to connect these actions with existing booking and shopping services.

## App Highlights

- A salon-first experience centered on past treatments and the next visit.
- A quick view of upcoming actions, appointments, and reminders.
- Product replacement estimates that start with a user-defined interval and later use the same product's usage history.
- Local-first data storage, with iCloud sync planned for supported devices.

## Features

The planned initial release includes:

- Salon visit records with treatments, staff, photos, and notes; reference photos and an order summary to show a stylist.
- Separate timing and reminders for treatments such as cuts and coloring, plus links to external booking services.
- Cosmetics and fragrance records, including individual purchased items, usage history, replacement reminders, and repurchase links.
- An in-app monthly calendar for beauty appointments, with optional Google Calendar integration.
- Export of records and photos.

These features are not implemented yet. The initial release does not include manufacturer expiry dates or period-after-opening tracking.

## Tech Stack

- **Currently in the project:** Swift, SwiftUI, Xcode, and XCTest targets.
- **Planned:** SwiftData, CloudKit, UserNotifications, PhotosPicker, Google OAuth, and the Google Calendar API.

The planned architecture is local-first, without a dedicated app backend for the initial release.

## Local Setup

1. Install Xcode on macOS and make an iOS 26.5 or later simulator available. The Xcode project currently sets iOS 26.5 as its deployment target.
2. Clone this private repository: `git clone https://github.com/okuda1506/BeautyArchive.git` (GitHub access is required).
3. Open `BeautyArchive.xcodeproj` in Xcode.
4. Select the `BeautyArchive` scheme and an available simulator, then run the app.

The current app displays a starter screen. Google Calendar credentials and other integrations are not required to run it at this stage.

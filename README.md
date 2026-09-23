# Beauty Archive

[日本語](README.ja.md)

## Overview

Beauty Archive is an iOS app for keeping beauty records, schedules, and next actions together. Development is at an early stage; the current app is a SwiftUI starter screen, and the features below describe the planned initial release. Requirements may change as the project develops.

## Background

Beauty-related activities are spread across more services and places than one might expect.

For a salon visit, booking often happens through a booking service, the appointment lives in a calendar, hairstyle references are in a photo app, and the details of the previous treatment depend on memory or notes.

Cosmetics and fragrances are similarly fragmented: purchase history is on an online store, opening dates are remembered rather than recorded, and replacement timing is often a guess. The information people need is rarely in one place.

This creates small but recurring inconveniences:

- Not knowing when the last salon visit was.
- Forgetting what hairstyle was requested last time.
- Spending time looking for a reference photo to show the stylist.
- Not knowing when a cosmetic product was bought or opened.
- Missing the right time to rebook or replace a product.
- Having beauty appointments, records, and photos scattered across apps.

Beauty Archive is being developed to bring those records and next actions together.

Its concept is:

> **An archive for beauty history and a reminder for the next beauty action, in one app.**

Rather than being only a place to log beauty activities, it aims to connect the full sequence naturally:

```text
Record
↓
Review
↓
Know when to act next
↓
Book or purchase
```

### What Beauty Archive aims to do

Beauty Archive is not intended to replace existing salon booking services or online stores. People can continue to use those services to book appointments and buy products. Beauty Archive supports the steps around them:

- Recording beauty history.
- Saving photos and order details.
- Tracking when the next action is due.
- Managing beauty appointments.
- Providing paths back to booking and purchasing services.

This makes Beauty Archive a **hub for managing beauty activities** across services.

### Approach to the iOS app

The app is currently being developed exclusively for iOS. It uses SwiftUI and Apple platform capabilities to create a simple, polished experience that feels natural on iPhone.

The planned data layer uses SwiftData and CloudKit / iCloud, without requiring a separate Beauty Archive account. Users should be able to begin using the app without a complicated sign-up process, with supported data synced across devices on the same Apple Account through iCloud.

Google Calendar integration is also planned. A Google account will authorize access to calendar features only; it will not be used to sign in to Beauty Archive.

### UI / UX principles

Although this is a beauty management app, the interface should avoid excessive decoration and aim for the simplicity and refinement of Apple's native apps. The design prioritizes:

- Making photos the focus.
- Showing only the information needed.
- Keeping forms and recording steps short.
- Making the next beauty action immediately clear.
- Using native Apple UI patterns.
- Bringing Liquid Glass into controls and navigation.

The central experience is **making it easy to keep recording, then making those records useful for the next beauty action**.

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

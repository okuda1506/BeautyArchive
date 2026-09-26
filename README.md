# B/ONE

[日本語](README.ja.md)

## Overview

B/ONE is a personal beauty management platform that brings beauty records, schedules, photos, and reminders together. Requirements may change as the project develops.

## What is B/ONE?

B/ONE brings salon treatment history, hairstyle reference photos, cosmetics and fragrance management, maintenance timing, and Google Calendar events into one place.

Beauty information is often scattered across multiple apps and services. B/ONE aims to connect the full sequence naturally:

**Record → Review → Know when to act next → Book or purchase**

B/ONE is not intended to replace salon booking services or online stores. It is designed as a **hub for managing the beauty experience around those existing services**.

> **Beauty, all in one.**

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

B/ONE is being developed to bring those records and next actions together.

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

### What B/ONE aims to do

B/ONE is not intended to replace existing salon booking services or online stores. People can continue to use those services to book appointments and buy products. B/ONE supports the steps around them:

- Recording beauty history.
- Saving photos and order details.
- Tracking when the next action is due.
- Managing beauty appointments.
- Providing paths back to booking and purchasing services.

This makes B/ONE a **hub for managing beauty activities** across services.

### Approach to the iOS app

The app is currently being developed exclusively for iOS. It uses SwiftUI and Apple platform capabilities to create a simple, polished experience that feels natural on iPhone.

The planned data layer uses SwiftData and CloudKit / iCloud, without requiring a separate B/ONE account. Users should be able to begin using the app without a complicated sign-up process, with supported data synced across devices on the same Apple Account through iCloud.

Google Calendar integration is also planned. A Google account will authorize access to calendar features only; it will not be used to sign in to B/ONE.

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

**Available now:** Salon visit records and photos, hairstyle references and a stylist-facing summary, treatment timing with a one-week notification snooze or a one-time due-date change, and local beauty appointments in a monthly calendar. The calendar also supports cosmetics and perfume purchase plans; marking one purchased adds a single item purchase record. Products support images, per-purchase usage records, replacement estimates and local reminders, and repurchase links. Home brings salon and product actions together. Settings provides local notification controls, a JSON export of records and saved photos, and optional Google Calendar account authorization. Connected users can see Google events read-only in the monthly calendar and choose which B/ONE appointments to reflect in their Google primary calendar. Local appointments remain saved if Google sync fails, with a status and retry action. Google authorization, event loading, and write-back have not yet been verified with a real account.

**Still planned:** iCloud sync is configured but has not been verified across devices. Google write-back across multiple devices also needs real-world validation. The initial release does not include manufacturer expiry dates or period-after-opening tracking.

## Tech Stack

- **Currently in the project:** Swift, SwiftUI, SwiftData, CloudKit, PhotosPicker, UserNotifications, Google OAuth, Google Calendar API, Xcode, and XCTest targets.

The planned architecture is local-first, without a dedicated app backend for the initial release.

## Local Setup

1. Install Xcode on macOS and make an iOS 26.5 or later simulator available. The Xcode project currently sets iOS 26.5 as its deployment target.
2. Clone the repository: `git clone https://github.com/okuda1506/BeautyArchive.git`.
3. Open `BeautyArchive.xcodeproj` in Xcode.
4. Select the `BeautyArchive` scheme and an available simulator, then run the app.

The app stores records locally. Google Calendar authorization is optional; the iOS OAuth client ID and callback scheme are already configured in the project, so no additional credentials are needed to build it. Testing Google authorization requires a Google account permitted by the project's OAuth consent screen and an enabled Google Calendar API.

To check Google Calendar write requests without a simulator or Google account, run `bash scripts/check-google-calendar-writer.sh` on macOS. This uses a local URLProtocol mock and does not verify live Google authorization or API behavior.

Run `bash scripts/check-google-account-binding.sh` to check that an account switch cannot return the new account's token to an in-flight calendar operation. This uses an in-memory credential store.

Before a release, follow the [Google Calendar real-account QA checklist (Japanese)](docs/GoogleCalendarManualQA.ja.md). These live-account checks have not yet been performed.

Use the [iCloud cross-device QA checklist (Japanese)](docs/ICloudManualQA.ja.md) to verify records, photos, and appointments on two devices. Cross-device behavior has not yet been tested.

Reminder timing choices use iCloud key-value storage, while notification permission and the on/off switch remain device-specific. Cross-device preference sync has not yet been verified on real devices.

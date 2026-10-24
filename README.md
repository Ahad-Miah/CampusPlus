# CampusPlus

CampusPlus is a Flutter campus issue reporting app backed by Firebase Authentication and Cloud Firestore, with Cloudinary-hosted issue and profile photos.

## Run on Android

1. Install Flutter and Android Studio, then start an Android emulator.
2. Enable **Email/Password** in Firebase Console → Authentication → Sign-in method.
3. Create a Cloud Firestore database and publish the rules in [`firestore.rules`](./firestore.rules).
4. Confirm the configured unsigned Cloudinary upload preset has the restrictions described in [`SETUP_GUIDE.md`](./SETUP_GUIDE.md).
5. Deploy the push-notification Cloud Function from [`functions/`](./functions/), if the Firebase project billing plan allows it.
6. Run `flutter pub get`, then `flutter run -d emulator-5554`. On Windows, [`run-emulator.ps1`](./run-emulator.ps1) handles the non-ASCII workspace path.

Firebase Android settings are configured for project `campusplus-210d8` and package `com.example.app`. The local Android client file is `android/app/google-services.json`. For another Firebase project, replace that file and regenerate [`firebase_options.dart`](./lib/firebase_options.dart) using FlutterFire CLI. Never add service-account credentials to the app.

## Features
- Email/password registration and login without mandatory email verification, password reset, and sign-out
- Student-only public registration; Admin/Staff roles must be assigned by a trusted administrator
- Automatic dashboard routing from the Firestore account role
- Branded startup splash screen and first-launch, skippable onboarding
- Role-aware navigation drawers plus responsive bottom navigation/rail
- Admin-created Staff accounts with department details and direct email/password sign-in
- Admin-requested Staff inspections before repair assignment
- Staff work logs with completed and remaining steps plus optional repair photos, visible on every issue
- Clickable dashboard summaries and issue cards that open the matching reports
- Live Firestore issue list, search, status filters, issue detail and timeline
- Responsive Updates activity feed with staff notes, completed/remaining steps, photos, and complete issue timelines
- Student My Issues page to track, edit photos/details on unassigned reports, or delete owned reports
- Admin Manage All Issues page with search/status filters and reporter-approved deletion of resolved issues
- Live unread notification counts and deletion-approval alerts that open approve/decline actions without entering the issue workflow
- Home issue cards with photo-led priority/status badges, location and details action; five recent issues are shown on the dashboard
- Report form with category, building/floor/room, severity and anonymous toggle
- Optional issue/profile photo uploads to Cloudinary; secure image URLs are saved in Firestore
- Similar open issue check, one-time affected votes, and persistent issue following
- Automatic severity/impact/age priority, Admin override, department assignment and expected completion date
- Staff-confirmed inspections before Admin repair assignment; Staff can document work, attach progress/completion photos, and explicitly submit a resolution summary
- Android launcher icon uses the supplied CampusPlus graduation illustration
- Only affected students can verify resolutions; reopening requires a strict majority of affected students
- Issue creation, assignment, inspection, and staff progress notifications, push alerts, and notification history (after Cloud Function deployment); duplicate issue events are suppressed
- Profile editing, account settings, support requests, student suggestions and Admin review tools
- Analytics by category/building, recurrence, resolution time and expected-date SLA
- Anonymous reporter IDs stored in restricted documents, with Admin migration for legacy reports
- Autosaved, account-specific report drafts with retry when connectivity returns

Sign in with email and password; CampusPlus loads the account role from Firestore and opens the matching dashboard. Public registration creates Student accounts. The trusted project owner bootstraps the first Admin in Firebase Console; that Admin can create Staff accounts in Profile → Manage accounts. The app does not send verification emails. See [`SETUP_GUIDE.md`](./SETUP_GUIDE.md) for the first-Admin setup steps.

The first app launch shows a branded splash screen followed by three short onboarding screens; users can swipe, skip, or tap **Get Started**. Onboarding is remembered on the device and will not interrupt later launches.

Issue workflow: Admin assigns a Staff member to inspect a new report. That Staff member confirms or rejects the inspection with a note. Only a confirmed issue can then be assigned by Admin for repair. The assigned Staff member posts progress updates with completed and remaining steps; all signed-in users can follow activity in Updates and open the issue details for its full timeline. Students manage their submissions in My Issues. Admins can request deletion of a resolved report, but the reporter must approve; approval deletes the issue, its progress records, linked notifications, and user-facing issue indexes automatically. Cloudinary-hosted image files are not removed by Firestore cleanup.

For security, the app does not hard-code a shared `admin@gmail.com` account or password. Create the desired email/password account through Firebase Authentication (using a real mailbox you control), then promote its Firestore profile to `admin` as described in the setup guide.

Cloud Functions deployment requires Firebase Cloud Messaging and may require the Firebase project to be on the Blaze billing plan. See [`SETUP_GUIDE.md`](./SETUP_GUIDE.md) before deployment.

## Project structure
```
lib/
  main.dart
  app.dart
  firebase_options.dart
  models/campus_issue.dart
  services/firebase_issue_repository.dart
```

Read [`SETUP_GUIDE.md`](./SETUP_GUIDE.md) for Firebase setup, security rules, Cloudinary setup, role assignment, and push notification deployment.

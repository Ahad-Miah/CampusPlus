# CampusPlus — Setup guide (Bangla + English)

এই guide অনুসরণ করে নিজের কম্পিউটারে project চালাবে। **নিজের password বা Cloudinary API secret chat-এ পাঠাবে না।** Firebase client config ও Cloudinary unsigned upload preset public client configuration; Admin SDK private key বা Cloudinary API secret কখনো Flutter app-এ রাখবে না।

## A. Android run

1. Flutter SDK install করো: https://docs.flutter.dev/get-started/install
2. Android Studio install করে Android SDK + emulator setup করো।
3. VS Code-এ Flutter ও Dart extensions install করো।
4. Project folder VS Code-এ Open করো।
5. Terminal:
   ```bash
   flutter doctor
   flutter pub get
   flutter run -d emulator-5554
   ```

On a fresh installation, the app shows a CampusPlus splash screen and a short three-page onboarding walkthrough before sign-in. Onboarding can be skipped and is remembered on that device.

## B. Firebase project and Android config

This workspace is currently configured for Firebase project `campusplus-210d8` and Android package `com.example.app`.

To use a different Firebase project:
1. Firebase Console → Project settings → General → add an Android app with package `com.example.app`.
2. Download `google-services.json` and replace `android/app/google-services.json`.
3. Run FlutterFire CLI to regenerate `lib/firebase_options.dart`:
   ```bash
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure --project YOUR_PROJECT_ID --platforms android
   ```
4. Run `flutter pub get`.

The provided `google-services.json` is a Firebase client config, not an Admin SDK credential. Never put service-account private keys in the Flutter app.

## C. Email and password authentication

Firebase Console → Build → Authentication → Get started:
- Email/Password enable করো।
- App login, student registration, password reset, and sign-out Firebase Auth দিয়ে চলে। অ্যাপ email verification বাধ্যতামূলক করে না এবং verification email পাঠায় না।
- Public registration সবসময় `student` role তৈরি করে। Sign-up form দিয়ে Admin/Staff হওয়া সম্ভব নয়।
- As requested, no university-domain allowlist or email-verification requirement is enforced.

**প্রথম Admin তৈরি:** project owner একটি বাস্তবভাবে নিয়ন্ত্রিত email দিয়ে app-এ account তৈরি করবে। Firebase Console → Authentication থেকে account-এর `uid` নিয়ে Firestore-এর তৈরি হওয়া `users/{uid}` document-এ `role` value `admin` করো। Role edit করার সময় শুধু অনুমোদিত project owner-ই করবে; email address নয়, Authentication UID ব্যবহার করবে। `admin@gmail.com`-এর মতো shared default account/password app-এ hard-code করা নেই—নিজের নিয়ন্ত্রিত mailbox-এ account তৈরি করো এবং password নিরাপদে সেট করো।

## D. Firestore database and rules

Firebase Console → Build → Firestore Database → Create database.
Deploy the current rules before using this client; signed-in Firebase accounts are authorized by their Firestore roles, and anonymous reporter data remains private:
```bash
firebase deploy --only firestore:rules
```
The app uses `users/{uid}`, `users/{uid}/reportedIssues/{issueId}`, `issues/{issueId}`, a restricted `issues/{issueId}/private/reporter` record, and per-issue `affectedBy/{uid}`, `followers/{uid}`, and `verificationVotes/{uid}` documents. The user-scoped issue index lets students open **My issues** without exposing reporter UIDs in public issue documents. The reporter is automatically marked as affected; other students must confirm impact before resolution to be eligible to verify it. Reopening requires a strict majority of the affected-student count. Student suggestions are saved under `suggestions/{suggestionId}` for Admin review. On first Admin sign-in, the app migrates legacy public `reporterUid` fields to the restricted reporter record and creates the reporter's issue index; keep the updated rules deployed so that migration is authorized.

Admin assignment records the responsible department and expected completion date. Priority is calculated from severity, affected-student count, and age; an Admin can override it. Staff must enter a resolution summary when submitting completed work. Analytics report category/building totals, recurring locations, recorded resolution time, and SLA performance where expected dates are available.

Report forms autosave per account on the device. If connectivity is lost during submission, the draft (including an attached photo) is retained and automatically retried when the app is connected again. Cloudinary photo upload itself still requires an internet connection.

## E. Cloudinary photo uploads

Cloudinary is used instead of Firebase Storage so image uploads do not need a Firebase Storage bucket or Blaze billing.

1. In Cloudinary Console → **Settings** → **Upload** → **Upload presets**, create an unsigned upload preset.
2. Restrict the preset to JPG, PNG, and WebP; set the maximum file size to 5 MB; choose the `campusplus` asset folder; and keep overwrite disabled. Unsigned presets are public, so keep these limits in place and monitor Cloudinary usage.
3. This project is configured with cloud name `be4i3h7e` and upload preset `campusplus_preset`. These are public upload settings, not API secrets. Confirm they match your Cloudinary account and preset; never put your API secret in the app.
4. Launch the app with the configured values:
   ```powershell
   .\run-emulator.ps1
   ```
   To use a different Cloudinary account, pass its cloud name and unsigned preset to the launcher or provide Dart defines directly:
   ```powershell
   flutter run -d emulator-5554 --dart-define=CLOUDINARY_CLOUD_NAME=YOUR_CLOUD_NAME --dart-define=CLOUDINARY_UPLOAD_PRESET=YOUR_UNSIGNED_PRESET
   ```

Issue and profile images accept JPG, PNG, or WebP files up to 5 MB. Cloudinary's HTTPS `secure_url` is saved as `photoUrl` on the issue or user profile document in Firestore. These image URLs are public to anyone who obtains them; Firestore access rules do not make the Cloudinary asset private.

## F. Push notifications and Functions

Android notification permission is requested when push notifications are enabled in Profile → Settings. Issue updates are also saved in the in-app Updates screen. The Cloud Function sends FCM notifications to opted-in devices and writes notification history; when deployed, it also sends the resolved-issue deletion approval request to the reporting student's opted-in devices.

Install the Functions dependencies and deploy (requires eligible Firebase billing):
```bash
npm --prefix functions install
firebase deploy --only functions
```
Deploy Firestore rules and the function together when updating the project:
```bash
firebase deploy --only firestore:rules,functions
```
Cloud Functions deployment may require the Firebase project to be on the **Blaze** billing plan. The current project is on Spark and has not been upgraded; push delivery through the Cloud Function therefore remains unavailable until billing is explicitly enabled. Do not add a service-account key to the Flutter app.

## G. Admin and Staff accounts

Every public sign-up creates a Student account. For the first Admin, set the trusted owner's account document in Firestore → `users/{uid}` to `role: "admin"`. The next sign-in automatically opens the Admin dashboard; there is no role picker. In Profile → Manage accounts, select **Add staff member** and enter the staff member's name, email, department, optional phone number, and a temporary password. The account is created in Firebase Authentication and given the `staff` role in Firestore without signing out the Admin. Give the credentials to the staff member securely; the app does not store the password. Staff use those credentials in the regular sign-in form and are routed to the Staff dashboard. No one can choose or assign themselves an elevated role through public registration.

Issue handling happens in two separate staff stages: Admin requests an inspection from a selected Staff account; that Staff member opens **Tasks**, inspects the reported problem, and records whether it is actually damaged plus an inspection note. After the Staff member confirms it, Admin can assign the repair to any Staff account. The assigned worker starts the repair, posts updates with completed and remaining steps (and optional work photos), then explicitly submits a resolution summary with an optional completion photo. **Updates** contains issue activity, staff notes, completed/remaining steps, photos, and notifications; selecting an activity opens the complete issue timeline. Students can open **My issues**, edit or delete their own unassigned reports, and see live status and staff work. Admins can open **Manage all issues**, filter/search all reports, and request deletion approval for a resolved report. The request is sent to its reporter; approving it in **My issues** deletes the issue immediately, with no second Admin action. Deploy the updated `firestore.rules` after changing these Firestore permissions.

An `admin@gmail.com` identity cannot be safely invented by the app: it must be a real Firebase Authentication account, and its owner must set/receive the password securely. To use that address, create it through Firebase Authentication first, then have the trusted project owner set its matching Firestore profile role to `admin`. Never publish or reuse a default password.

## H. Verification
1. Run `flutter analyze` and fix warnings/errors.
2. Run `flutter test`.
3. Test splash/login/registration, role routing, staff account creation, Firestore rules, issue reporting, status changes, and voting on an Android emulator.
4. Test on a real phone before production use. Enable Firebase App Check before onboarding real students. No email verification or university-domain allowlist is required. Analytics shown in the app are live aggregates of the issues visible to the signed-in user; they are not an audited institutional report.

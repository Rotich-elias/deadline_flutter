# Deadlines&Notes

A task list that sorts itself by what is due next and colours each item by how
close it is. Everything is stored on the device first; syncing — to a Laravel
server or to your own Google Drive — is optional and happens in the
background.

## Colour scale

| Time left | Colour | Group |
|---|---|---|
| Past due | Red `#FF3355` | Overdue |
| Under 6 hours | Orange `#FF6B2C` | Due now |
| Under 24 hours | Amber `#FFA51F` | Today |
| Under 3 days | Yellow `#E4C441` | Next few days |
| Under 7 days | Green `#46C08A` | This week |
| Beyond that | Blue `#5C8DEF` | Later |

The thin bar under each card is a one-week pressure gauge: empty when the task
is a week out, full at the deadline. Colours re-evaluate every 30 seconds and
again whenever the app is resumed, so a card shifts from green to amber to red
without you touching anything.

## Running the app

```bash
flutter pub get
flutter run
```

The Android project is already configured (Java 17, core library desugaring,
`minSdk 24`, notification receivers, widget provider and the upload signing
config). Do not regenerate `android/` over it.

Builds:

```bash
flutter test
flutter analyze
flutter clean && flutter build appbundle --release
```

The release build deliberately fails if `android/key.properties` is missing or
points at a missing keystore, instead of silently falling back to the debug key.
See `PLAY_STORE_DEPLOYMENT.md`.

Build the APK with `flutter build apk --release`; the file lands in
`build/app/outputs/flutter-apk/`.

## Reminders

Each task schedules two local notifications — one day before and one hour
before. They are rescheduled on every edit, cancelled when a task is completed
or deleted, and restored after a reboot via the boot receiver.

Android 13+ requires notification permission; the app asks after the first
frame so the prompt can never delay launch. Android 14+ does not grant exact
alarms by default, so reminders are scheduled inexactly (Android may delay them
by a few minutes) until the user allows exact timing from **menu → Reminders &
digest**. The app never opens the system alarms screen on its own. If Android
rejects an exact alarm, scheduling automatically retries as an inexact alarm
rather than failing.

## Sync (optional)

Skip this entirely if you only ever use one phone. The app is fully functional
with sync switched off. Pick one of two backends from the sync sheet (menu →
*Sync settings*) — they're mutually exclusive, not layered.

### Option A — Google Drive

No server to run. Open **APIs & Services → Credentials** in the
[Google Cloud console](https://console.cloud.google.com) for a project with
the Drive API enabled, create an **OAuth client ID** of type **Android**, and
give it:

- Package name: `com.deadline.app.deadline`
- SHA-1 fingerprint of your signing key (debug key: `keytool -list -v
  -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass
  android -keypass android`)

Also add your own account as a **test user** on the OAuth consent screen while
developing. `drive.appdata` is a non-sensitive scope, so Google does not require
the app to complete sensitive-scope verification, but the OAuth consent screen
must be published before people outside your test-user list can sign in.
Nothing needs to be pasted into the app — Android matches the client by package
name + fingerprint automatically. Then on the phone: menu → *Sync settings* →
*Google Drive* → *Sign in with Google*.

Tasks and notes each get their own JSON file in the app's private Drive
`appDataFolder` — invisible in the user's normal Drive UI, and only this app
can read it. There's no server-side database, so every sync downloads the
whole file, merges in local changes (newest `updated_at` wins), and re-uploads
the merged set. Uploads send the ETag the file was read at, so if another
device writes in between, Drive rejects the stale upload and the app retries the
whole merge. Tombstones older than 30 days are dropped from the file so it
doesn't grow forever.

### Option B — your own Laravel server

Copy the files in `backend/` into a Laravel app with Sanctum installed:

- `2026_07_23_000000_create_tasks_table.php` → `database/migrations/`
- `2026_07_24_000000_create_notes_table.php` → `database/migrations/`
- `2026_10_23_000000_add_synced_at_to_tasks_and_notes.php` → `database/migrations/`
- `Task.php`, `Note.php` → `app/Models/`
- `SyncController.php`, `NoteSyncController.php` → `app/Http/Controllers/`
- merge `api_routes.php` into `routes/api.php`

```bash
php artisan migrate
php artisan tinker
>>> App\Models\User::first()->createToken('phone')->plainTextToken
```

**Phone side** — menu → *Sync settings* → *Your server* → paste the server
address and the token, then Save. The address must use `https://`; the app
rejects plain HTTP so the token is never sent in clear text. The token is stored
in Android's Keystore-backed secure storage.

One endpoint, `POST /api/tasks/sync`. The device sends every row flagged
`dirty` plus the timestamp of its last successful sync; the server merges those
in, then returns everything with a server-stamped `synced_at` at or after that
timestamp. Pull filtering uses the server clock, not the device's
`updated_at`, so a phone with a slow clock cannot miss changes forever.

### Conflict handling (both backends)

Conflicts resolve by `updated_at` — the more recent edit wins on both sides.
Deletions travel as tombstones (`deleted = true`) rather than dropped rows,
which is what stops a task you deleted on the phone from being resurrected by
the laptop on the next pull. Tombstones are purged locally once the backend
acknowledges them.

Sync fires on launch, on resume, three seconds after any edit, when the network
comes back, and on pull-to-refresh. A small cloud icon on each card marks rows
that have not made it up yet.

## Privacy

There are no ads, analytics or crash-reporting SDKs. See `PRIVACY_POLICY.md`
(also available in the app under **menu → Privacy policy**) for the full
policy. Android Auto Backup is disabled, so the local database is not copied
into Google's cloud backup.

## Layout

```
lib/
  models/task.dart               data shape + sync metadata
  data/local_db.dart             sqflite schema and queries
  data/task_store.dart           what the UI listens to; ticks the clock
  sync/sync_backend.dart         the interface api_client and drive_backend share
  sync/api_client.dart           Laravel backend over HTTP
  sync/drive_backend.dart        Google Drive appDataFolder backend
  sync/sync_service.dart         push, pull, merge, retry — backend-agnostic
  services/notifications.dart
  services/home_widget_service.dart  pushes the next deadline to the home screen widget
  utils/urgency.dart             the colour and countdown rules
  ui/                            list, card, forms
  ui/privacy_page.dart           in-app copy of PRIVACY_POLICY.md
test/                            unit tests for recurrence, reminders and sync URLs
```

The urgency rules live in one file on purpose. Change the thresholds or the
palette in `utils/urgency.dart` and the whole app follows.

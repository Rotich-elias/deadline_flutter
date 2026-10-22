# Privacy policy for Deadlines&Notes

**Effective 23 October 2026**

Deadlines&Notes is an offline-first deadline and note tracker. This policy
explains what stays on your device and what happens when you choose to turn on
optional sync.

## What the app stores

Deadlines&Notes stores your tasks, notes, tags and app settings in a local
database on your device. Reminder times, the daily digest time and the
appearance setting are stored with Android's local preferences. Nothing is sent
anywhere unless you turn on sync.

## Optional sync

Sync is off by default. If you enable it, the app transfers tasks and notes over
an encrypted HTTPS connection to the destination you choose: either your own
Google Drive app-private folder, or a server you configure yourself. The
developer does not operate a shared server and cannot read your data.

## Google Drive

When you sign in with Google, the app requests only the `drive.appdata` scope.
That scope can access only the hidden application-data folder created by this
app; it cannot read the rest of your Drive. You can revoke access at any time
from your Google Account permissions page.

## Your own server

If you connect a server, the access token is kept in the Android
Keystore-backed secure storage, not in ordinary app preferences. The server
operator (you, or whoever runs that server) is responsible for the data stored
there.

## Notifications

Reminders and the optional daily digest are scheduled locally by Android. The
app requests notification permission, and optionally exact-alarm permission so
a reminder fires at the time you chose. Notification contents are generated on
your device and are not sent to a push service.

## Analytics, ads and sharing

The app contains no advertising, analytics, tracking or crash reporting SDKs.
It does not sell or share personal data with third parties. The only network
requests are the sync requests you configure, plus Google sign-in if you choose
Drive sync.

## Backups

Android cloud backup and device-to-device transfer are disabled for this app, so
its database and settings are not copied into a Google backup.

## Deleting your data

You can delete individual tasks and notes inside the app, or remove all local
data by clearing the app's storage or uninstalling it. If sync is on, delete the
data in the app while online so the deletion is also written to Drive or your
server. You can remove Drive access from your Google Account at any time.

## Children

The app is a general productivity tool, is not directed at children under 13,
and does not knowingly collect personal information from them.

## Changes to this policy

If this policy changes, the updated version will ship with the app and be
published at the same URL. The effective date above shows when it last changed.

## Contact

Use the developer email address shown on the app's Google Play listing.

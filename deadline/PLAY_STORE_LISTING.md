# Play Store listing copy (ready to paste)

## Title (≤ 30 chars)
Deadlines&Notes

## Short description (≤ 80 chars)
Offline-first task & note tracker sorted by what's due next. Optional sync.

## Full description (≤ 4000 chars)
Deadlines&Notes is a task list that sorts itself by what is due next and colours
each item by how close it is, so the thing that needs your attention is always at
the top.

Everything is stored on the device first, so it works offline and fast. Syncing
is optional and happens silently in the background — to your own Google Drive
(app-data folder) or to your own Laravel server. No account is required to use
the app.

Colour scale (pressure gauge under each card):
• Past due — red
• Under 6 hours — orange
• Under 24 hours — amber
• Under 3 days — yellow
• Under 7 days — green
• Beyond — blue
The bar under each card is a one-week pressure gauge: empty when a task is a
week away, full at the deadline. Colours re-evaluate every 30 seconds and on
resume, so a card shifts from green to amber to red without you touching it.

Reminders
Each task schedules two local notifications — one day before and one hour
before. They're rescheduled on every edit, cancelled when a task completes or
is deleted, and restored after a reboot. The closest-due reminder can surface
over the lock screen so you never miss it.

Notes
Keep lightweight notes alongside your tasks, with the same colour/closest-first
sorting where applicable.

Home screen widget
A widget shows your next deadline right on the home screen and refreshes as
things approach.

Sync (optional, you choose the backend)
• Google Drive — no server to run; data lives in your app's private Drive
  appDataFolder (invisible in normal Drive, only this app can read it).
• Your own server — point the app at your Laravel API with a Sanctum token.
• Offline — do nothing; the app is fully functional single-device.

Privacy
No ads, no analytics, no data leaves the device unless you explicitly enable
sync. When sync is on, tasks and notes go only to the destination you pick.

## Tags / keywords (for ASO — used in description)
deadline, task list, to-do, reminders, offline, notes, urgency, colour coded

## Release notes — v1.0.0
Initial release: offline-first task & note tracker with colour-coded urgency,
local reminders with reboot restore, home screen widget, optional sync to Google
Drive or your own Laravel server.

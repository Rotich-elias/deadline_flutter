package com.deadline.app.deadline

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.location.LocationManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.CalendarContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.RecognizerIntent
import android.util.Log
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "deadline/notifications"
    private val securityChannelName = "deadline/security"
    private val platformChannelName = "deadline/platform"
    private var methodChannel: MethodChannel? = null

    private var pendingPhotoResult: MethodChannel.Result? = null
    private var pendingTranscriptResult: MethodChannel.Result? = null
    private var pendingPermissionAction: (() -> Unit)? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var audioPath: String? = null
    private var quickNoteLaunch = false
    private val proximityIntents = mutableSetOf<PendingIntent>()

    companion object {
        private const val REQ_CAMERA = 701
        private const val REQ_AUDIO = 702
        private const val REQ_SPEECH = 703
        private const val REQ_CALENDAR_READ = 704
        private const val REQ_CALENDAR_WRITE = 705
        private const val REQ_LOCATION = 706
        private const val LOCATION_CHANNEL = "deadline_location"
        private const val QUICK_NOTE_EXTRA = "deadline_quick_note"
    }

    /**
     * Text shared into the app while Dart was not listening yet (cold start,
     * or the moment the engine comes up). Dart drains this with
     * `takeSharedNotes`. Each entry carries the text plus the shared file's
     * display name, which is where Samsung Notes keeps the note's title.
     */
    private val pendingShares = mutableListOf<Map<String, String>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        quickNoteLaunch = intent?.getBooleanExtra(QUICK_NOTE_EXTRA, false) == true
        installQuickShortcut()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openChannelSettings" -> result.success(
                    openChannelSettings(call.argument<String>("channelId"))
                )
                "takeSharedNotes" -> {
                    val payload = pendingShares.toList()
                    pendingShares.clear()
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        collectShared(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureScreen" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capturePhoto" -> capturePhoto(result)
                    "startAudioRecording" -> startRecording(result)
                    "stopAudioRecording" -> result.success(stopRecording())
                    "transcribe" -> transcribe(result)
                    "currentLocation" -> currentLocation(result)
                    "addProximityAlert" -> addProximityAlert(call, result)
                    "clearProximityAlerts" -> clearProximityAlerts(call, result)
                    "calendarEvents" -> calendarEvents(call, result)
                    "addCalendarEvent" -> addCalendarEvent(call, result)
                    "takeQuickNote" -> {
                        result.success(quickNoteLaunch)
                        quickNoteLaunch = false
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(QUICK_NOTE_EXTRA, false)) {
            quickNoteLaunch = true
            // The Dart side may already be running, so tell it about the new
            // shortcut request instead of relying on the cold-start flag.
            methodChannel?.invokeMethod("quickNote", null)
        }
        collectShared(intent)
    }

    // --- Existing share/channel helpers --------------------------------

    private fun collectShared(intent: Intent?) {
        val texts = extractSharedTexts(intent)
        if (texts.isEmpty()) return
        pendingShares.addAll(texts)
        methodChannel?.invokeMethod("sharedNotes", null)
    }

    private fun extractSharedTexts(intent: Intent?): List<Map<String, String>> {
        if (intent == null) return emptyList()
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return emptyList()
        }

        val shares = mutableListOf<Map<String, String>>()
        intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { text ->
                val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()
                shares.add(
                    if (subject.isNullOrEmpty()) mapOf("text" to text)
                    else mapOf("text" to text, "name" to subject)
                )
            }

        @Suppress("DEPRECATION")
        val streams: List<Uri> = if (intent.action == Intent.ACTION_SEND) {
            listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM))
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM) ?: emptyList()
        }

        for (uri in streams) {
            try {
                val name = displayName(uri)
                contentResolver.openInputStream(uri)?.use { input ->
                    val text = input.readBytes().toString(Charsets.UTF_8).trim()
                    if (text.isNotEmpty()) {
                        shares.add(
                            if (name.isNullOrBlank()) mapOf("text" to text)
                            else mapOf("text" to text, "name" to name)
                        )
                    }
                }
            } catch (e: Exception) {
                Log.w("DeadlineShare", "Could not read shared note $uri", e)
            }
        }
        return shares
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
        )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
    } catch (e: Exception) {
        Log.w("DeadlineShare", "Could not read display name for $uri", e)
        null
    }

    private fun openChannelSettings(channelId: String?): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && channelId != null) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            }
        }
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    // --- Quick note launcher shortcut ----------------------------------

    private fun installQuickShortcut() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = "com.deadline.app.deadline.QUICK_NOTE"
                putExtra(QUICK_NOTE_EXTRA, true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val shortcut = android.content.pm.ShortcutInfo.Builder(this, "quick_note")
                .setShortLabel("Quick note")
                .setLongLabel("New note in Deadlines&Notes")
                .setIcon(android.graphics.drawable.Icon.createWithResource(
                    this, R.drawable.ic_launcher_foreground
                ))
                .setIntent(intent)
                .build()
            val manager = getSystemService(ShortcutManager::class.java)
            manager?.setDynamicShortcuts(listOf(shortcut))
        } catch (e: Exception) {
            Log.w("DeadlineShortcut", "Could not install quick note shortcut", e)
        }
    }

    // --- Camera / audio / speech capture --------------------------------

    private fun capturePhoto(result: MethodChannel.Result) {
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        if (intent.resolveActivity(packageManager) == null) {
            result.success(null)
            return
        }
        pendingPhotoResult = result
        startActivityForResult(intent, REQ_CAMERA)
    }

    private fun hasPermission(permission: String) =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun startRecording(result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.RECORD_AUDIO)) {
            pendingPermissionAction = { startRecording(result) }
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.RECORD_AUDIO), REQ_AUDIO
            )
            return
        }
        try {
            val file = File(cacheDir, "voice_${System.currentTimeMillis()}.m4a")
            val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION") MediaRecorder()
            }
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setOutputFile(file.absolutePath)
            mediaRecorder.prepare()
            mediaRecorder.start()
            recorder = mediaRecorder
            audioPath = file.absolutePath
            result.success(file.absolutePath)
        } catch (e: Exception) {
            Log.w("DeadlineAudio", "Could not start recorder", e)
            result.success(null)
        }
    }

    private fun stopRecording(): String? = try {
        recorder?.apply {
            try { stop() } catch (_: Exception) {}
            release()
        }
        recorder = null
        audioPath
    } catch (e: Exception) {
        Log.w("DeadlineAudio", "Could not stop recorder", e)
        null
    }

    private fun transcribe(result: MethodChannel.Result) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak the meeting notes…")
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.success(null)
            return
        }
        pendingTranscriptResult = result
        startActivityForResult(intent, REQ_SPEECH)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_CAMERA) {
            val bitmap = data?.extras?.get("data") as? Bitmap
            val path = if (bitmap != null && resultCode == RESULT_OK) {
                try {
                    val file = File(filesDir, "photo_${System.currentTimeMillis()}.jpg")
                    FileOutputStream(file).use { out ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    }
                    file.absolutePath
                } catch (e: Exception) {
                    Log.w("DeadlineCamera", "Could not save photo", e)
                    null
                }
            } else null
            pendingPhotoResult?.success(path)
            pendingPhotoResult = null
        }
        if (requestCode == REQ_SPEECH) {
            val text = if (resultCode == RESULT_OK) {
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                    ?.firstOrNull()
            } else null
            pendingTranscriptResult?.success(text)
            pendingTranscriptResult = null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (!granted) {
            // A denied permission still has to answer the waiting Dart call.
            pendingPermissionAction = null
            pendingPermissionResult?.success(null)
            pendingPermissionResult = null
            return
        }
        pendingPermissionResult = null
        pendingPermissionAction?.invoke()
        pendingPermissionAction = null
    }

    // --- Location alerts and device calendar ---------------------------

    private fun currentLocation(result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.ACCESS_FINE_LOCATION) &&
            !hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        ) {
            pendingPermissionAction = { currentLocation(result) }
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                REQ_LOCATION
            )
            return
        }
        result.success(currentLocationMap())
    }

    private fun currentLocationMap(): Map<String, Double>? {
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null
        val location = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .firstNotNullOfOrNull { provider ->
                try {
                    @Suppress("MissingPermission")
                    manager.getLastKnownLocation(provider)
                } catch (_: Exception) {
                    null
                }
            }
        return location?.let {
            mapOf("latitude" to it.latitude, "longitude" to it.longitude)
        }
    }

    private fun proximityPending(id: String, label: String): PendingIntent {
        val intent = Intent(this, LocationAlertReceiver::class.java).apply {
            putExtra("label", label)
        }
        return PendingIntent.getBroadcast(
            this,
            id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun addProximityAlert(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") ?: run { result.success(false); return }
        val lat = call.argument<Double>("latitude") ?: run { result.success(false); return }
        val lon = call.argument<Double>("longitude") ?: run { result.success(false); return }
        val radius = call.argument<Double>("radiusMeters") ?: 200.0
        val label = call.argument<String>("label") ?: "Deadline nearby"
        if (!hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) {
            pendingPermissionAction = { addProximityAlert(call, result) }
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), REQ_LOCATION
            )
            return
        }
        result.success(try {
            val pending = proximityPending(id, label)
            val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            @Suppress("MissingPermission")
            manager.addProximityAlert(lat, lon, radius.toFloat(), -1, pending)
            proximityIntents.add(pending)
            true
        } catch (e: Exception) {
            Log.w("DeadlineGeofence", "Could not add proximity alert", e)
            false
        })
    }

    private fun clearProximityAlerts(call: MethodCall, result: MethodChannel.Result) {
        val ids = call.argument<List<String>>("ids")
        val targets = if (ids.isNullOrEmpty()) {
            proximityIntents.toList()
        } else {
            ids.map { proximityPending(it, "") }
        }
        result.success(try {
            val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            @Suppress("MissingPermission")
            targets.forEach(manager::removeProximityAlert)
            proximityIntents.clear()
            true
        } catch (e: Exception) {
            Log.w("DeadlineGeofence", "Could not clear proximity alerts", e)
            false
        })
    }

    private val eventProjection = arrayOf(
        CalendarContract.Events._ID,
        CalendarContract.Events.TITLE,
        CalendarContract.Events.DTSTART
    )

    private fun calendarEvents(call: MethodCall, result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.READ_CALENDAR)) {
            pendingPermissionAction = { calendarEvents(call, result) }
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.READ_CALENDAR), REQ_CALENDAR_READ
            )
            return
        }
        val from = call.argument<Long>("from") ?: run { result.success(emptyList<Map<String, Any>>()); return }
        val to = call.argument<Long>("to") ?: run { result.success(emptyList<Map<String, Any>>()); return }
        val events = mutableListOf<Map<String, Any>>()
        try {
            contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                eventProjection,
                "${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} <= ?",
                arrayOf(from.toString(), to.toString()),
                "${CalendarContract.Events.DTSTART} ASC"
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    events.add(
                        mapOf(
                            "id" to cursor.getLong(0).toString(),
                            "title" to (cursor.getString(1) ?: ""),
                            "start" to cursor.getLong(2)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.w("DeadlineCalendar", "Could not read calendar", e)
        }
        result.success(events)
    }

    private fun addCalendarEvent(call: MethodCall, result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.WRITE_CALENDAR)) {
            pendingPermissionAction = { addCalendarEvent(call, result) }
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.WRITE_CALENDAR), REQ_CALENDAR_WRITE
            )
            return
        }
        val title = call.argument<String>("title") ?: run { result.success(false); return }
        val start = call.argument<Long>("start") ?: run { result.success(false); return }
        val minutes = call.argument<Int>("durationMinutes") ?: 60
        result.success(try {
            val values = ContentValues().apply {
                put(CalendarContract.Events.DTSTART, start)
                put(CalendarContract.Events.DTEND, start + minutes * 60_000L)
                put(CalendarContract.Events.TITLE, title)
                put(CalendarContract.Events.CALENDAR_ID, defaultCalendarId())
                put(CalendarContract.Events.EVENT_TIMEZONE, java.util.TimeZone.getDefault().id)
            }
            contentResolver.insert(CalendarContract.Events.CONTENT_URI, values) != null
        } catch (e: Exception) {
            Log.w("DeadlineCalendar", "Could not write calendar", e)
            false
        })
    }

    private fun defaultCalendarId(): Long {
        // CAL_ACCESS_CONTRIBUTOR is a hidden framework constant (400), so read
        // the access level ourselves and fall back to the first writable
        // calendar rather than depending on a hidden API.
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(
                CalendarContract.Calendars._ID,
                CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndex(CalendarContract.Calendars._ID)
            val accessColumn =
                cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
            while (cursor.moveToNext()) {
                val access = if (accessColumn >= 0) cursor.getInt(accessColumn) else 0
                if (access >= 400 && idColumn >= 0) return cursor.getLong(idColumn)
            }
            if (idColumn >= 0 && cursor.moveToFirst()) return cursor.getLong(idColumn)
        }
        return 1L
    }
}

/** Fires the local notification when Android reports arrival at a saved place. */
class LocationAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val label = intent.getStringExtra("label") ?: "Deadline nearby"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    LOCATION_CHANNEL, "Location reminders",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
        }
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, LOCATION_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_map)
            .setContentTitle("You're near $label")
            .setContentText("A deadline here? Open Deadlines&Notes to check.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        @Suppress("MissingPermission")
        manager.notify(System.currentTimeMillis().toInt(), notification)
    }

    companion object {
        private const val LOCATION_CHANNEL = "deadline_location"
    }
}

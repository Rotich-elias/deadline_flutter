package com.deadline.app.deadline

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "deadline/notifications"
    private var methodChannel: MethodChannel? = null

    /**
     * Text shared into the app while Dart was not listening yet (cold start,
     * or the moment the engine comes up). Dart drains this with
     * `takeSharedNotes`. Each entry carries the text plus the shared file's
     * display name, which is where Samsung Notes keeps the note's title.
     */
    private val pendingShares = mutableListOf<Map<String, String>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openChannelSettings" -> {
                    val channelId = call.argument<String>("channelId")
                    result.success(openChannelSettings(channelId))
                }
                "takeSharedNotes" -> {
                    val payload = pendingShares.toList()
                    pendingShares.clear()
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        collectShared(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        collectShared(intent)
    }

    /**
     * Remembers anything shared into the app and nudges Dart to collect it.
     * Both plain text and text files are accepted, because Samsung Notes
     * sends an exported note as a `.txt` stream when you pick "Text file".
     */
    private fun collectShared(intent: Intent?) {
        val texts = extractSharedTexts(intent)
        if (texts.isEmpty()) return
        pendingShares.addAll(texts)
        methodChannel?.invokeMethod("sharedNotes", null)
    }

    private fun extractSharedTexts(intent: Intent?): List<Map<String, String>> {
        if (intent == null) return emptyList()
        if (intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE
        ) {
            return emptyList()
        }

        val shares = mutableListOf<Map<String, String>>()
        intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let { text ->
                val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()
                shares.add(
                    if (subject.isNullOrEmpty()) {
                        mapOf("text" to text)
                    } else {
                        mapOf("text" to text, "name" to subject)
                    }
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
                            if (name.isNullOrBlank()) {
                                mapOf("text" to text)
                            } else {
                                mapOf("text" to text, "name" to name)
                            }
                        )
                    }
                }
            } catch (e: Exception) {
                Log.w("DeadlineShare", "Could not read shared note $uri", e)
            }
        }
        return shares
    }

    /** The name the sharing app gave the file, e.g. "Jobs to be paid.txt". */
    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            Log.w("DeadlineShare", "Could not read display name for $uri", e)
            null
        }
    }

    /**
     * Android keeps a notification channel's sound, importance and pop-up
     * behaviour fixed after creation, so the only real way to change the tone
     * is the system page for that channel. Below Android 8 there are no
     * channels, so app notification settings are the closest equivalent.
     */
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
}

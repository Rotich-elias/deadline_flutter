package com.deadline.app.deadline

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "deadline/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openChannelSettings" -> {
                        val channelId = call.argument<String>("channelId")
                        result.success(openChannelSettings(channelId))
                    }
                    else -> result.notImplemented()
                }
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

package com.stocktrack.stock_track

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var voiceBridge: HarnessVoiceBridge? = null
    private var micPcmRecorder: MicPcmRecorder? = null

    companion object {
        // Harness push parity: the notification channel FCM posts orchestrator replies to
        // on Android 8+. Must match push.androidChannelId in harness/project.config.json
        // and the default_notification_channel_id meta-data in AndroidManifest.xml.
        private const val PUSH_CHANNEL_ID = "stocktrack_ops_channel"
        private const val PUSH_CHANNEL_NAME = "Stock-Track Ops"
        private const val PUSH_CHANNEL_DESC =
            "Replies from the Stock-Track orchestrator and build/dogfood updates."
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Harness voice-to-text mic (native SpeechRecognizer, no Flutter speech
        // plugin → no Firebase/web dependency conflict). The proven default engine.
        voiceBridge = HarnessVoiceBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // Raw PCM capture for the bundled offline engine (sherpa-onnx). Inert
        // unless the Dart engine flag selects the offline engine.
        micPcmRecorder = MicPcmRecorder(this, flutterEngine.dartExecutor.binaryMessenger)
        // Create the harness push channel so a background/terminated FCM notification has
        // a valid channel to post on (Android 8+ drops notifications with no channel).
        createPushChannel()
    }

    private fun createPushChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            PUSH_CHANNEL_ID,
            PUSH_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = PUSH_CHANNEL_DESC }
        manager.createNotificationChannel(channel)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == HarnessVoiceBridge.PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            voiceBridge?.onPermissionResult(granted)
        }
    }
}

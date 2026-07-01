package com.stocktrack.stock_track

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var voiceBridge: HarnessVoiceBridge? = null
    private var micPcmRecorder: MicPcmRecorder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Harness voice-to-text mic (native SpeechRecognizer, no Flutter speech
        // plugin → no Firebase/web dependency conflict). The proven default engine.
        voiceBridge = HarnessVoiceBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // Raw PCM capture for the bundled offline engine (sherpa-onnx). Inert
        // unless the Dart engine flag selects the offline engine.
        micPcmRecorder = MicPcmRecorder(this, flutterEngine.dartExecutor.binaryMessenger)
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

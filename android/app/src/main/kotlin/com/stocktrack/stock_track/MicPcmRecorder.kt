package com.stocktrack.stock_track

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Raw microphone PCM capture for the bundled offline speech engine (sherpa-onnx,
 * in `packages/harness_voice/`). Ported verbatim from the reference mic pattern.
 *
 * Streams 16 kHz mono PCM16 to Dart over an [EventChannel]; the Dart side
 * converts to float and feeds the recognizer. Deliberately NATIVE rather than a
 * Flutter audio package: `record` / `flutter_sound` transitively pull
 * `package:web ^1.x`, which can conflict with a Firebase-v2 host app's `web`
 * pin. A bare [AudioRecord] over a platform channel touches zero shared Dart deps.
 *
 * Uses `VOICE_RECOGNITION` audio source so the platform applies its STT-tuned
 * noise suppression / AGC — a free win for noisy capture. Mic permission is
 * granted via the voice-bridge flow; this recorder only checks it.
 *
 * Gated upstream by the Dart engine flag (default is the system engine), so it's
 * inert unless the bundled offline engine is selected.
 */
class MicPcmRecorder(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "harness/voice_pcm"
        const val EVENT_CHANNEL = "harness/voice_pcm/events"
        const val SAMPLE_RATE = 16000
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var recordThread: Thread? = null

    @Volatile
    private var recording = false
    private var audioRecord: AudioRecord? = null

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> startRecording(result)
            "stop" -> {
                stopRecording()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun hasMicPermission(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun startRecording(result: MethodChannel.Result) {
        if (recording) {
            result.success(true)
            return
        }
        if (!hasMicPermission()) {
            result.success(false)
            sendError("Microphone permission not granted")
            return
        }

        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuf <= 0) {
            result.success(false)
            sendError("AudioRecord unavailable on this device")
            return
        }
        // At least ~200ms of buffering so a busy main thread never starves it.
        val bufSize = maxOf(minBuf, SAMPLE_RATE / 5 * 2)

        val recorder = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufSize,
            )
        } catch (e: Exception) {
            result.success(false)
            sendError(e.message ?: "AudioRecord init failed")
            return
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            result.success(false)
            sendError("AudioRecord failed to initialize")
            return
        }

        audioRecord = recorder
        recording = true
        recorder.startRecording()

        // Read on a daemon thread; ship each ~100ms chunk to Dart on the main thread.
        recordThread = Thread {
            val chunk = ByteArray(SAMPLE_RATE / 10 * 2) // 100ms of PCM16
            while (recording) {
                val n = recorder.read(chunk, 0, chunk.size)
                if (n > 0) {
                    val out = if (n == chunk.size) chunk.copyOf() else chunk.copyOf(n)
                    mainHandler.post { events?.success(out) }
                }
            }
        }.also {
            it.isDaemon = true
            it.start()
        }
        result.success(true)
    }

    private fun stopRecording() {
        recording = false
        recordThread?.join(300)
        recordThread = null
        audioRecord?.let { r ->
            try {
                r.stop()
            } catch (_: Exception) {
                // best-effort
            }
            r.release()
        }
        audioRecord = null
    }

    private fun sendError(message: String) {
        mainHandler.post {
            events?.success(mapOf("type" to "error", "message" to message))
        }
    }
}

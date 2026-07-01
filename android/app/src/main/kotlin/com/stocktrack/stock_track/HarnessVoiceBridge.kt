package com.stocktrack.stock_track

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Native bridge for the harness voice-to-text mic (the reusable-harness standard,
 * ported verbatim from the reference mic pattern).
 *
 * App-owned Android [SpeechRecognizer] behind a [MethodChannel] (start/stop) +
 * an [EventChannel] (final-text / status / error). Deliberately NO Flutter speech
 * plugin: an app-owned recognizer over a platform channel runs while the owner
 * NAVIGATES the app (the keyboard mic only feeds a focused field with the
 * keyboard up), and a plain platform channel touches zero shared Dart deps so it
 * never drags a `web` dependency into a Firebase-v2 host app.
 *
 * Continuous capture: Android's recognizer finalizes + stops after a short
 * silence, so on each onResults/onError we re-arm startListening() while the
 * user still wants to listen — narration feels continuous across pauses. A word
 * at the exact restart seam can rarely drop (accepted trade-off).
 *
 * Perf lesson (baked in): we REUSE one [SpeechRecognizer] for the whole listening
 * session instead of destroy()+create() on every utterance. The original churn
 * paid a fresh IPC bind to the system recognition service (+ a cold start, + a
 * deaf window) on every silence gap — that is exactly "cutting out" + a
 * progressive slowdown (rapid bind/unbind degrades the recognition service over a
 * session). We only drop+recreate the recognizer on a genuine wedge
 * (ERROR_RECOGNIZER_BUSY / ERROR_CLIENT). We also tune the silence windows so a
 * natural pause mid-sentence does NOT finalize (= fewer re-arm seams = fewer
 * dropped words). Re-arm delay is short (60ms) since there's no teardown to wait on.
 *
 * Beep suppression: the platform recognizer plays a "ready"/"end" tone on each
 * `startListening`, and our auto-restart fires one per silence → repeated beeps.
 * We mute the output streams those tones use (music/system/notification) for the
 * WHOLE listening session (muted on start, restored on stop/permanent-error), so
 * the per-restart beeps stay silent. Output-only — muting playback never affects
 * mic capture. Ring/alarm streams are left ALONE (never miss a call/alarm).
 *
 * On-device preference: prefer ON-DEVICE recognition to match the reliability/
 * latency of the keyboard mic. Android 12+ (API 31) →
 * `createOnDeviceSpeechRecognizer`; API 23–30 → the normal recognizer with
 * `EXTRA_PREFER_OFFLINE`. **Safe fallback:** if the device has no on-device
 * language pack (`ERROR_LANGUAGE_UNAVAILABLE` / `ERROR_LANGUAGE_NOT_SUPPORTED`),
 * we flip to the online recognizer for the rest of the session and re-arm — so
 * worst case = the old online behaviour, never silent. Toggled from Dart via the
 * `preferOnDevice` start-arg. Partial results are emitted live for the transcript.
 */
class HarnessVoiceBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, RecognitionListener {

    companion object {
        const val METHOD_CHANNEL = "harness/voice_stt"
        const val EVENT_CHANNEL = "harness/voice_stt/events"

        /** Arbitrary request code; unlikely to clash with other plugins. */
        const val PERMISSION_REQUEST_CODE = 0xB0B
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var events: EventChannel.EventSink? = null

    /** User intent: the mic toggle is ON. Drives the native auto-restart loop. */
    private var wantListening = false

    /** Caller's preference: attempt on-device recognition. */
    private var preferOnDevice = true

    /** Sticky for the session once the device proves it has no offline pack. */
    private var offlineUnavailable = false

    /** Whether the CURRENT recognizer instance is the on-device one. */
    private var onDeviceActive = false

    /**
     * Last partial transcript for the CURRENT recognition session. In continuous
     * dictation Android frequently ends a session with `onError` (NO_MATCH /
     * SPEECH_TIMEOUT) rather than `onResults`, then we re-arm — which used to
     * DISCARD that session's recognized words (many partial cycles, ZERO
     * onResults, only the last partial survived). We now commit this as a `final`
     * on session-end so no phrase is lost. Cleared when committed (here or via a
     * real `onResults`) so each session commits exactly once.
     *
     * ALSO reset at every USER session boundary (`start` / `stop`), NOT just the
     * internal auto-restart re-arm. A recognizer is reused across the silence gaps
     * WITHIN one listening turn, but a user stop/start must begin a clean turn.
     * Without this reset the previous turn's accumulated partial survived, and the
     * next turn's first (shorter) partial tripped the reset-detect in
     * [onPartialResults] → it committed the PRIOR sentence as a `final`, which
     * prepended the last sentence onto the new dictation. The internal re-arm path
     * ([startListeningInternal] via [reArmIfWanted]) deliberately does NOT clear
     * it, so within-turn accumulation across pauses still works.
     */
    private var lastPartial = ""

    private val audioManager: AudioManager by lazy {
        activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    /** Output streams the recognizer's start/stop tones play on (NOT ring/alarm). */
    private val beepStreams = intArrayOf(
        AudioManager.STREAM_MUSIC,
        AudioManager.STREAM_SYSTEM,
        AudioManager.STREAM_NOTIFICATION,
    )
    private var beepsMuted = false

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    // --- MethodChannel ---

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" ->
                result.success(SpeechRecognizer.isRecognitionAvailable(activity))
            "start" -> {
                if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
                    result.success(false)
                    sendEvent(
                        "error",
                        mapOf("permanent" to true, "message" to "No speech recognizer on this device"),
                    )
                    return
                }
                if (!hasMicPermission()) {
                    // Request once; the user re-taps the mic after granting.
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        PERMISSION_REQUEST_CODE,
                    )
                    sendEvent("status", mapOf("value" to "needs_permission"))
                    result.success(false)
                    return
                }
                // Dart toggle; default on. A fresh tap re-attempts on-device in
                // case a language pack was downloaded since a prior fallback.
                preferOnDevice = call.argument<Boolean>("preferOnDevice") ?: true
                offlineUnavailable = false
                // A fresh USER recording starts a clean turn: drop any partial left
                // over from the previous turn so it can't be re-committed
                // (prepended) as a `final` by the reset-detect on the first new partial.
                lastPartial = ""
                wantListening = true
                setBeepsMuted(true)
                startListeningInternal()
                result.success(true)
            }
            "stop" -> {
                wantListening = false
                stopListeningInternal()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // --- EventChannel ---

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    // --- Permission ---

    private fun hasMicPermission(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    /** Forwarded from [MainActivity.onRequestPermissionsResult]. */
    fun onPermissionResult(granted: Boolean) {
        if (granted) {
            // Auto-start so the user doesn't have to tap the mic a second time.
            wantListening = true
            setBeepsMuted(true)
            startListeningInternal()
        } else {
            wantListening = false
            sendEvent(
                "error",
                mapOf("permanent" to true, "message" to "Microphone permission denied"),
            )
        }
    }

    // --- Recognizer lifecycle (all on the main thread) ---

    /**
     * Reuse one recognizer for the whole session; create it lazily on first
     * arm (and after a wedge clears it to null). Reusing avoids the per-utterance
     * IPC rebind that caused the sluggishness/cut-outs.
     */
    private fun ensureRecognizer(): SpeechRecognizer {
        recognizer?.let { return it }
        // On-device path: Android 12+ (API 31) has a dedicated guaranteed-local
        // recognizer. Use it unless the caller opted out or the device already
        // proved it has no offline pack this session (then fall back to the
        // normal recognizer, which may route online).
        // Direct SDK_INT guard at the call site so lint's NewApi check is happy
        // (createOnDeviceSpeechRecognizer is API 31+).
        val r = if (preferOnDevice && !offlineUnavailable &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        ) {
            onDeviceActive = true
            SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
        } else {
            onDeviceActive = false
            SpeechRecognizer.createSpeechRecognizer(activity)
        }
        r.setRecognitionListener(this)
        recognizer = r
        return r
    }

    private fun buildRecognizerIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            // Prefer on-device when we're NOT already on the dedicated on-device
            // recognizer (i.e. API 23–30, or after a fallback). On API 31+ the
            // on-device recognizer is inherently local, so this is redundant there.
            if (preferOnDevice && !offlineUnavailable && !onDeviceActive &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
            ) {
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
            // Don't finalize on every micro-pause: keep a natural sentence inside
            // ONE recognition session so we re-arm far less often. Each re-arm is
            // the "cutting out" seam where a word can drop, so fewer = better.
            // int extras (the recognizer reads them with getInt) — NOT Long.
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                1800,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                1800,
            )
        }

    private fun startListeningInternal() {
        mainHandler.post {
            if (!wantListening) return@post
            val r = try {
                ensureRecognizer()
            } catch (e: Exception) {
                sendEvent(
                    "error",
                    mapOf("permanent" to false, "message" to (e.message ?: "create failed")),
                )
                return@post
            }
            try {
                r.startListening(buildRecognizerIntent())
                sendEvent(
                    "status",
                    mapOf("value" to "listening", "onDevice" to onDeviceActive),
                )
            } catch (e: Exception) {
                // A start failure usually means the instance wedged — drop it so
                // the next re-arm builds a clean one, then surface for re-arm.
                recognizer?.destroy()
                recognizer = null
                sendEvent(
                    "error",
                    mapOf("permanent" to false, "message" to (e.message ?: "start failed")),
                )
            }
        }
    }

    private fun stopListeningInternal() {
        mainHandler.post {
            recognizer?.cancel()
            recognizer?.destroy()
            recognizer = null
            // The user ended this turn; the in-flight final tail is already flushed
            // Dart-side from its live transcript, so clear the native accumulator
            // too. This guarantees `lastPartial` never survives a user stop/start
            // boundary and leaks into the next recording.
            lastPartial = ""
            setBeepsMuted(false)
            sendEvent("status", mapOf("value" to "stopped"))
        }
    }

    /**
     * Mute/unmute the recognizer's beep streams for the listening session.
     * Idempotent via [beepsMuted]; best-effort (a mute failure never breaks
     * recognition). API 23+ uses ADJUST_MUTE/UNMUTE.
     */
    private fun setBeepsMuted(muted: Boolean) {
        if (muted == beepsMuted) return
        beepsMuted = muted
        for (stream in beepStreams) {
            try {
                audioManager.adjustStreamVolume(
                    stream,
                    if (muted) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE,
                    0,
                )
            } catch (_: Exception) {
                // best-effort — never let a mute failure break dictation
            }
        }
    }

    /**
     * Restart after a recognition session ends, so dictation stays continuous.
     * Short delay only (no teardown to wait on now we reuse the instance); just
     * enough to clear the current callback frame before startListening again.
     */
    private fun reArmIfWanted() {
        if (!wantListening) return
        mainHandler.postDelayed({ if (wantListening) startListeningInternal() }, 60)
    }

    private fun sendEvent(type: String, extra: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>(extra)
        payload["type"] = type
        mainHandler.post { events?.success(payload) }
    }

    // --- RecognitionListener ---

    override fun onResults(results: Bundle?) {
        val text = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
        if (!text.isNullOrBlank()) {
            // Authoritative final — supersede the accumulated partial.
            sendEvent("final", mapOf("text" to text))
            lastPartial = ""
        }
        // If blank (Android frequently returns an EMPTY onResults for on-device
        // continuous recognition), KEEP lastPartial: the next session's
        // reset-detect (onPartialResults) or the Dart flush-on-stop will commit
        // it. Do NOT clear it here, or the session's words are lost.
        reArmIfWanted()
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val text = partialResults
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
        if (!text.isNullOrBlank()) {
            // Session-restart detection (the REAL fix): in continuous dictation the
            // recognizer silently restarts its utterance — partials jump back to a
            // short fresh string — and ends sessions with NO usable
            // onResults/onError commit. So when a new partial is SHORTER than the
            // accumulated one, the prior session ended: commit its words as a
            // `final` BEFORE adopting the new partial. Path-independent — works
            // regardless of which callback (if any) fired. Within a session
            // partials only grow, so a shrink = a genuine restart, not a revision.
            if (lastPartial.isNotBlank() && text.length < lastPartial.length) {
                sendEvent("final", mapOf("text" to lastPartial))
            }
            lastPartial = text
            sendEvent("partial", mapOf("text" to text))
        }
    }

    override fun onError(error: Int) {
        // Only a denied permission is truly permanent here; NO_MATCH /
        // SPEECH_TIMEOUT / BUSY etc. are normal in continuous mode → re-arm.
        if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
            wantListening = false
            setBeepsMuted(false)
            sendEvent(
                "error",
                mapOf("permanent" to true, "message" to "Microphone permission denied"),
            )
            return
        }
        // (Session-end words are captured by the reset-detect in onPartialResults
        // + the Dart flush-on-stop. Nothing to commit here.)
        // No on-device language pack on this device → fall back to the online
        // recognizer for the rest of the session (sticky) and re-arm, so the mic
        // is never silently dead. Worst case = the old online behaviour.
        if (onDeviceActive &&
            (error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ||
                error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED)
        ) {
            offlineUnavailable = true
            recognizer?.destroy()
            recognizer = null
            sendEvent("status", mapOf("value" to "fallback_online"))
            reArmIfWanted()
            return
        }
        // Reuse the instance across normal end-of-utterance errors (NO_MATCH /
        // SPEECH_TIMEOUT). Only a genuine wedge — the recognizer reports BUSY or
        // a client-side fault — warrants dropping + recreating it.
        if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY ||
            error == SpeechRecognizer.ERROR_CLIENT
        ) {
            recognizer?.destroy()
            recognizer = null
        }
        reArmIfWanted()
    }

    override fun onReadyForSpeech(params: Bundle?) {}
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onEvent(eventType: Int, params: Bundle?) {}
}

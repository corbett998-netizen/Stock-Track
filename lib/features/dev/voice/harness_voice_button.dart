import 'package:flutter/material.dart';

import 'harness_report_draft.dart';
import 'harness_voice_config.dart';
import 'harness_voice_service.dart';

/// The floating voice-to-text mic button for the harness — ported from the
/// reference mic pattern. Lives in the draggable dev-tool cluster (above the
/// Navigator, so NO Tooltip: it would need an Overlay ancestor the cluster lacks).
///
/// Tap to start dictating into the shared [HarnessReportDraft]; tap again to stop.
/// Long-press (while idle) A/Bs the engine (phone vs bundled offline). While
/// listening it shows a pulsing mic + a live transcript chip so it's obvious the
/// mic is hot and the owner sees words landing while they keep using the app.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — no project noun. State comes from
/// [HarnessVoiceService] (a ChangeNotifier singleton).
class HarnessVoiceButton extends StatefulWidget {
  const HarnessVoiceButton({super.key, this.bare = true, this.size = 44});

  /// When true (cluster use), render ONLY the mic core at a CONSTANT footprint so
  /// the growing live transcript can never reflow/shift the draggable cluster —
  /// the transcript floats in a fixed overlay to the LEFT instead. Non-bare
  /// self-positions bottom-right with an inline transcript pill (standalone use).
  final bool bare;

  /// FAB diameter — matched to the cluster's button size when bare.
  final double size;

  @override
  State<HarnessVoiceButton> createState() => _HarnessVoiceButtonState();
}

class _HarnessVoiceButtonState extends State<HarnessVoiceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Gentle scale pulse while listening; a fixed 1.0 when idle.
  Animation<double> _scaleFor(bool listening) {
    if (!listening) return const AlwaysStoppedAnimation<double>(1.0);
    return _pulse.drive(
      Tween<double>(begin: 1.0, end: 1.18)
          .chain(CurveTween(curve: Curves.easeInOut)),
    );
  }

  void _syncPulse(bool listening) {
    if (listening) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      if (_pulse.isAnimating) {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Repaint on BOTH the mic's listening/live state AND the draft's content, so
      // the "you have dictation waiting to file" cue is live without a provider.
      listenable: Listenable.merge(
        <Listenable>[HarnessVoiceService.instance, HarnessReportDraft.instance],
      ),
      builder: (context, _) {
        final voice = HarnessVoiceService.instance;
        final bool listening = voice.isListening;
        // Idle but the shared draft holds dictated words not yet filed → amber dot
        // hints "open File a report to submit" (the cluster reaches the mic draft).
        final bool draftPending =
            !listening && HarnessReportDraft.instance.isActive;
        _syncPulse(listening);
        // Which engine is active (long-press toggles it while idle):
        // "Offline" = bundled sherpa-onnx, "Phone" = the system engine.
        final bool sherpa =
            voice.engine == HarnessVoiceEngineKind.sherpaOnnx;

        final Widget mic = ScaleTransition(
          scale: _scaleFor(listening),
          child: GestureDetector(
            // Long-press (while idle) switches engine for in-app A/B — no rebuild.
            onLongPress: voice.cycleEngine,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: FloatingActionButton.small(
                heroTag: 'harness_voice_fab',
                // Idle colour encodes the engine: indigo = bundled offline,
                // blue-grey = phone engine; red = listening.
                backgroundColor: listening
                    ? Colors.red
                    : (sherpa ? Colors.indigo : Colors.blueGrey),
                foregroundColor: Colors.white,
                onPressed: voice.toggle,
                child: Icon(listening ? Icons.mic : Icons.mic_none, size: 20),
              ),
            ),
          ),
        );

        final String engineTag = sherpa ? 'Offline' : 'Phone';
        final String live = voice.liveTranscript.trim();
        final String pillText =
            live.isEmpty ? '$engineTag · Listening…' : live;

        // Bare (cluster): the mic is a CONSTANT-size Stack child; the transcript
        // pill is Positioned OUTSIDE it to the left (Clip.none) so it floats over
        // the live screen without ever changing the cluster's layout footprint.
        if (widget.bare) {
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              mic,
              if (listening)
                Positioned(
                  right: widget.size + 8,
                  child: _transcriptPill(pillText, live.isEmpty),
                ),
              if (draftPending)
                const Positioned(
                  top: -3,
                  right: -3,
                  child: _DraftDot(),
                ),
            ],
          );
        }

        // Non-bare (standalone): inline transcript pill to the LEFT of the mic.
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 90),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (listening) ...<Widget>[
                    _transcriptPill(pillText, live.isEmpty),
                    const SizedBox(width: 8),
                  ],
                  mic,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _transcriptPill(String text, bool italic) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}

/// A small amber dot on the idle mic when the shared draft holds dictated words
/// not yet filed — "open File a report to submit". Mirrors the report badge dot.
class _DraftDot extends StatelessWidget {
  const _DraftDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: const Color(0xFFFFB300), // amber
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1.5),
      ),
    );
  }
}

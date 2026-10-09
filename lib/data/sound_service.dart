import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show ServicesBinding;

/// Plays short, one-off UI sound effects. A completed task has nothing to
/// cancel or clean up, so unlike [NotificationService] this has no
/// initialize/dispose lifecycle beyond the player itself.
class SoundService {
  SoundService._();

  /// The check-off sound. Older options are still bundled: point this at
  /// `sounds/checkoff_click.wav` (volume 0.5) or `sounds/checkoff_chime.wav`
  /// (volume 0.35) to switch back.
  static const _checkoffAsset = 'sounds/checkoff_soft.wav';
  static const _checkoffVolume = 0.85;

  static final SoundService instance = SoundService._();

  AudioPlayer? _player;

  /// The short, soft tone played when a task (or, via its subtasks, a
  /// task's last remaining subtask) is checked off. Swallows errors —
  /// a missing/blocked audio output shouldn't ever stop a checkbox from
  /// toggling — and replays from the start if it's still finishing from a
  /// rapid previous check-off, rather than queuing or being dropped.
  ///
  /// Constructing [AudioPlayer] touches platform channels, and some of
  /// that setup happens in a fire-and-forget future that a try/catch
  /// around the construction call can't intercept — so when there's no
  /// Flutter binding at all yet (e.g. a plain `ProviderContainer` test
  /// with no widget binding), bail out before ever constructing it rather
  /// than relying on catching what it throws.
  Future<void> playCheckoff() async {
    try {
      ServicesBinding.instance;
    } catch (_) {
      return;
    }

    try {
      final player = _player ??= AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.play(AssetSource(_checkoffAsset), volume: _checkoffVolume);
    } catch (_) {
      // Best-effort: no audio output, unsupported platform, etc.
    }
  }
}

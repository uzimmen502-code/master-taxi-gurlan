import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marshrut panel: ONLINE / qo'lda TANAFFUS holat tovushlari.
class MarshrutPanelStatusSounds {
  MarshrutPanelStatusSounds._();

  static const _prefsKey = 'marshrut_panel_status_sounds_enabled';
  static const _cooldown = Duration(seconds: 2);

  static AudioPlayer? _player;
  static DateTime? _lastOnlineAt;
  static DateTime? _lastOfflineAt;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  static Future<void> playOnline() => _play(
        AssetSource('sounds/marshrut_online.wav'),
        lastPlayedAt: () => _lastOnlineAt,
        setLastPlayedAt: (v) => _lastOnlineAt = v,
      );

  static Future<void> playOffline() => _play(
        AssetSource('sounds/marshrut_offline.wav'),
        lastPlayedAt: () => _lastOfflineAt,
        setLastPlayedAt: (v) => _lastOfflineAt = v,
      );

  static Future<void> previewOnline() async {
    await _play(
      AssetSource('sounds/marshrut_online.wav'),
      ignoreCooldown: true,
      lastPlayedAt: () => _lastOnlineAt,
      setLastPlayedAt: (v) => _lastOnlineAt = v,
    );
  }

  static Future<void> previewOffline() async {
    await _play(
      AssetSource('sounds/marshrut_offline.wav'),
      ignoreCooldown: true,
      lastPlayedAt: () => _lastOfflineAt,
      setLastPlayedAt: (v) => _lastOfflineAt = v,
    );
  }

  static Future<void> _play(
    AssetSource source, {
    bool ignoreCooldown = false,
    required DateTime? Function() lastPlayedAt,
    required void Function(DateTime?) setLastPlayedAt,
  }) async {
    if (kIsWeb) return;
    if (!await isEnabled()) return;

    final now = DateTime.now();
    final previous = lastPlayedAt();
    if (!ignoreCooldown &&
        previous != null &&
        now.difference(previous) < _cooldown) {
      return;
    }
    setLastPlayedAt(now);

    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.setSource(source);
      await player.setVolume(0.85);
      await player.resume();
    } catch (e) {
      debugPrint('MarshrutPanelStatusSounds: $e');
    }
  }
}

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Mahalliy taksi: yangi chaqiruv kelganda qisqa signal.
class DriverOfferSounds {
  DriverOfferSounds._();

  static const _cooldown = Duration(seconds: 2);
  static AudioPlayer? _player;
  static DateTime? _lastPlayedAt;

  static Future<void> playNewOffer() async {
    if (kIsWeb) return;
    final now = DateTime.now();
    if (_lastPlayedAt != null &&
        now.difference(_lastPlayedAt!) < _cooldown) {
      return;
    }
    _lastPlayedAt = now;
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.setSource(AssetSource('sounds/marshrut_online.wav'));
      await player.setVolume(0.85);
      await player.resume();
    } catch (e) {
      debugPrint('DriverOfferSounds: $e');
    }
  }
}

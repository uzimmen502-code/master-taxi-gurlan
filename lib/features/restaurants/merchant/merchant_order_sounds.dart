// Ресторан панели: янги буюртмада қисқа сигнал + титраш.
// `DriverOfferSounds` билан бир хил ёндашув (мавжуд асset, cooldown).

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MerchantOrderSounds {
  MerchantOrderSounds._();

  static const _cooldown = Duration(seconds: 3);
  static AudioPlayer? _player;
  static DateTime? _lastPlayedAt;

  static Future<void> playNewOrder() async {
    final now = DateTime.now();
    if (_lastPlayedAt != null && now.difference(_lastPlayedAt!) < _cooldown) return;
    _lastPlayedAt = now;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
    if (kIsWeb) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.setSource(AssetSource('sounds/marshrut_online.wav'));
      await player.setVolume(1.0);
      await player.resume();
    } catch (e) {
      debugPrint('MerchantOrderSounds: $e');
    }
  }
}

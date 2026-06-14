import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Курьер «Етиб келдим» тугмасини босганда мижоз иловасида (foreground)
/// қўнғироқли огоҳлантиришни махсус ритмда ижро этади:
///   14 секунд тинимсиз жиринг → 10 секунд тинч → яна 14 секунд → 10 секунд тинч
///   → учинчи марта 14 секунд (жами 3 цикл), сўнг тўхтайди.
///
/// Илова фонда/ёпиқ бўлганда ритм OS томонидан кафолатланмайди —
/// у ҳолда `courier_arrival_alarm` канали овозни бир марта чалади.
class ArrivalRinger {
  ArrivalRinger._();
  static final ArrivalRinger instance = ArrivalRinger._();

  final FlutterRingtonePlayer _player = FlutterRingtonePlayer();

  Timer? _onTimer;
  Timer? _offTimer;
  bool _active = false;
  int _cycle = 0;

  static const int _ringSeconds = 14;
  static const int _silenceSeconds = 10;
  static const int _totalCycles = 3;

  bool get isRinging => _active;

  /// Ритмни бошлайди. Агар аллақачон жиринглаётган бўлса, қайта бошламайди.
  Future<void> start() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    if (_active) return;
    _active = true;
    _cycle = 0;
    _playCycle();
  }

  void _playCycle() {
    if (!_active) return;
    if (_cycle >= _totalCycles) {
      stop();
      return;
    }
    _cycle++;

    // 7 секунд тинимсиз жиринг (looping ringtone).
    try {
      _player.playRingtone(looping: true, volume: 1.0, asAlarm: false);
    } catch (_) {}

    _onTimer?.cancel();
    _onTimer = Timer(const Duration(seconds: _ringSeconds), () {
      try {
        _player.stop();
      } catch (_) {}
      if (!_active) return;
      if (_cycle >= _totalCycles) {
        // Охирги цикл — кейин тинч кутиш йўқ.
        stop();
        return;
      }
      // 10 секунд тинч, кейин кейинги цикл.
      _offTimer?.cancel();
      _offTimer = Timer(const Duration(seconds: _silenceSeconds), _playCycle);
    });
  }

  Future<void> stop() async {
    _active = false;
    _cycle = 0;
    _onTimer?.cancel();
    _offTimer?.cancel();
    _onTimer = null;
    _offTimer = null;
    try {
      await _player.stop();
    } catch (_) {}
  }
}

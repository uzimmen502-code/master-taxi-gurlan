import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'server_checkout.dart';

/// Қоровул: «клиент ↔ сервер мослиги» тестлари сервер манбалари йўқ
/// чекаутда `skip` бўлади (қаранг: `server_checkout.dart`). Агар янги сервер
/// (`index.js` ресторан/видео кодини ишлатади) бўлса-ю, мослик файлларидан
/// бири ЎЧИРИЛГАН бўлса — улар жимгина skip бўлиб, мослик назоратсиз қолади.
/// Шу тест уни ушлайди.
void main() {
  test('янги сервер чекаутида барча мослик манба файллари мавжуд', () {
    if (!serverIndexIsCurrent()) {
      // Эски deploy-линия: сервер кодсиз — мослик тестлари skip, бу нормал.
      return;
    }
    final missing = kServerParityFiles.where((f) => !File(f).existsSync()).toList();
    expect(
      missing,
      isEmpty,
      reason: 'functions/index.js янги сервер кодини ишлатади, лекин мослик '
          'тестлари ўқийдиган файллар йўқ: $missing — тестлар skip бўлиб, '
          'клиент↔сервер мослиги назоратсиз қолади',
    );
  });

  test('янги сервер чекаутида мослик тестлари ҲАҚИҚАТАН ишлайди (skip эмас)', () {
    if (serverIndexIsCurrent()) {
      expect(serverParitySkip, isNull);
    }
  });
}
import 'package:ava_gurlan/features/restaurants/domain/menu_scroll_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MenuScrollSync — chap ↔ o\'ng bog\'lanish', () {
    // 3 bo'lim: 2, 3, 1 ta taom; sarlavha 30, qator 100.
    final s = MenuScrollSync(sectionItemCounts: const [2, 3, 1], headerHeight: 30, itemHeight: 100);

    test('bo\'lim offsetlari — sarlavha + taomlar yig\'indisi', () {
      expect(s.sectionOffsets, [0, 230, 560]);
      expect(s.totalHeight, 690);
    });

    test('skroll → faol bo\'lim (sarlavhasi tepaga yetgan oxirgisi)', () {
      expect(s.sectionAt(0), 0);
      expect(s.sectionAt(229), 0);
      expect(s.sectionAt(230), 1);
      expect(s.sectionAt(400), 1);
      expect(s.sectionAt(559.4), 1, reason: '0.5 zaxira ichida emas');
      expect(s.sectionAt(559.5), 2, reason: '0.5 zaxira: 559.5 + 0.5 >= 560');
      expect(s.sectionAt(10000), 2);
      expect(s.sectionAt(-5), 0);
    });

    test('kategoriya bosildi → skroll manzili; maxScrollExtent bilan cheklanadi', () {
      expect(s.offsetOf(1), 230);
      expect(s.offsetOf(2), 560);
      expect(s.offsetOf(2, maxScrollExtent: 400), 400, reason: 'oxirgi qisqa bo\'lim');
      expect(s.offsetOf(7), 560, reason: 'indeks chegaralanadi');
      expect(s.offsetOf(-1), 0);
    });

    test('bosilgan bo\'limga borganda o\'sha bo\'lim faol bo\'ladi (aylanma izchillik)', () {
      for (var i = 0; i < s.sectionCount; i++) {
        expect(s.sectionAt(s.offsetOf(i)), i);
      }
    });

    test('bo\'sh menyu — xavfsiz', () {
      final e = MenuScrollSync(sectionItemCounts: const [], headerHeight: 30, itemHeight: 100);
      expect(e.sectionAt(100), 0);
      expect(e.offsetOf(0), 0);
      expect(e.totalHeight, 0);
    });
  });
}

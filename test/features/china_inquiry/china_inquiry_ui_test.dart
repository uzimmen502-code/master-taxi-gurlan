import 'package:ava_gurlan/features/china_inquiry/data/china_inquiry_repository.dart';
import 'package:ava_gurlan/features/china_inquiry/screens/china_inquiries_screen.dart';
import 'package:ava_gurlan/features/china_inquiry/screens/china_inquiry_form_screen.dart';
import 'package:ava_gurlan/features/china_inquiry/widgets/china_inquiry_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Локализациясиз `context.tr(key)` калитнинг ўзини қайтаради — тест калитни текширади
/// (3 тил паритетини `locale_sync_test` қулфлайди).
class _FakeRepo extends ChinaInquiryRepository {
  _FakeRepo({this.access = true, this.failTimes = 0});

  final bool access;
  int failTimes;
  final List<String> requestIds = [];
  int cancelled = 0;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<ChinaInquiryCreated> create({
    required String text,
    required String quantity,
    required String clientRequestId,
    String? productId,
  }) async {
    requestIds.add(clientRequestId);
    if (failTimes > 0) {
      failTimes--;
      throw Exception('network');
    }
    return const ChinaInquiryCreated(inquiryId: 'i1', refNo: 'CN-0007', duplicate: false);
  }

  @override
  Future<void> cancel(String inquiryId) async => cancelled++;

  @override
  Stream<List<ChinaInquiry>> watchMine(String phone) => Stream.value([
        const ChinaInquiry(
            id: 'i1', refNo: 'CN-0001', status: 'quoted', text: 'Samokat 500 dona', quantity: '', quoteCount: 1),
      ]);

  @override
  Stream<List<ChinaOffer>> watchOffers(String inquiryId) => Stream.value(const [
        ChinaOffer(
            id: 'q1', priceMinor: 3850, currency: 'USD', withdrawn: false, minOrderQty: 100, leadTimeDays: 20),
        ChinaOffer(id: 'q2', priceMinor: 100, currency: 'CNY', withdrawn: true),
      ]);
}

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  group('ChinaInquiryEntry', () {
    testWidgets('рухсат йўқ (OFF/тестер эмас) — ҳеч нарса кўрсатилмайди', (t) async {
      await t.pumpWidget(_app(Scaffold(
          body: ChinaInquiryEntry(phone: '998901234567', repository: _FakeRepo(access: false)))));
      await t.pumpAndSettle();
      expect(find.text('china_inq_banner_cta'), findsNothing);
    });

    testWidgets('рухсат бор — банер ва иккита тугма', (t) async {
      await t.pumpWidget(_app(Scaffold(
          body: ChinaInquiryEntry(phone: '998901234567', repository: _FakeRepo()))));
      await t.pumpAndSettle();
      expect(find.text('china_inq_banner_cta'), findsOneWidget);
      expect(find.text('china_inq_my'), findsOneWidget);
    });
  });

  group('ChinaInquiryFormScreen', () {
    testWidgets('қисқа матн рад, ҳеч нарса юборилмайди', (t) async {
      final repo = _FakeRepo();
      await t.pumpWidget(_app(ChinaInquiryFormScreen(repository: repo)));
      await t.enterText(find.byType(TextField).first, 'qisqa');
      await t.tap(find.text('china_inq_submit'));
      await t.pump();
      expect(find.text('china_inq_err_text'), findsOneWidget);
      expect(repo.requestIds, isEmpty);
    });

    testWidgets('розиликсиз рад', (t) async {
      final repo = _FakeRepo();
      await t.pumpWidget(_app(ChinaInquiryFormScreen(repository: repo)));
      await t.enterText(find.byType(TextField).first, 'Elektr samokat, yengil, 500 dona');
      await t.tap(find.text('china_inq_submit'));
      await t.pump();
      expect(find.text('china_inq_err_consent'), findsOneWidget);
      expect(repo.requestIds, isEmpty);
    });

    testWidgets('хато бўлса қайта уриниш ШУ ЗАХОТИ БИР ХИЛ калит билан (идемпотент)', (t) async {
      final repo = _FakeRepo(failTimes: 1);
      await t.pumpWidget(_app(ChinaInquiryFormScreen(repository: repo)));
      await t.enterText(find.byType(TextField).first, 'Elektr samokat, yengil, 500 dona');
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(find.text('china_inq_submit'));
      await t.pumpAndSettle();
      expect(find.text('china_inq_err_generic'), findsOneWidget, reason: 'ички xato matni ko‘rsatilmaydi');
      await t.tap(find.text('china_inq_submit'));
      await t.pumpAndSettle();
      expect(repo.requestIds.length, 2);
      expect(repo.requestIds[0], repo.requestIds[1]);
    });
  });

  group('ChinaInquiriesScreen', () {
    testWidgets('рўйхатда сўров ва ҳолат кўринади, босилса тафсилот очилади', (t) async {
      await t.pumpWidget(_app(ChinaInquiriesScreen(phone: '998901234567', repository: _FakeRepo())));
      await t.pumpAndSettle();
      expect(find.textContaining('CN-0001'), findsOneWidget);
      expect(find.text('china_inq_status_quoted'), findsOneWidget);
      await t.tap(find.textContaining('CN-0001'));
      await t.pumpAndSettle();
      expect(find.text('china_inq_offers'), findsOneWidget);
      expect(find.text('china_inq_offer_withdrawn'), findsOneWidget, reason: 'қайтариб олинган таклиф белгиланади');
    });

    test('таклиф нархи минор бирликдан матнга — double ишламайди', () {
      String p(int m) => ChinaOffer(id: 'x', priceMinor: m, currency: 'USD', withdrawn: false).priceText;
      expect(p(3850), '38.50');
      expect(p(5), '0.05');
      expect(p(100), '1.00');
      expect(p(1999), '19.99');
    });
    testWidgets('очиқ сўровни бекор қилиш: тасдиқ ойнаси, сўнг cancel чақирилади', (t) async {
      final repo = _FakeRepo();
      await t.pumpWidget(_app(ChinaInquiryDetailScreen(
        inquiry: const ChinaInquiry(
            id: 'i1', refNo: 'CN-0001', status: 'sent', text: 'Samokat 500 dona', quantity: '', quoteCount: 0),
        repository: repo,
      )));
      await t.pumpAndSettle();
      expect(find.text('china_inq_offers_none'), findsNothing, reason: 'fake 2 ta taklif beradi');
      await t.ensureVisible(find.text('china_inq_cancel'));
      await t.tap(find.text('china_inq_cancel'));
      await t.pumpAndSettle();
      await t.tap(find.text('china_inq_yes'));
      await t.pumpAndSettle();
      expect(repo.cancelled, 1);
    });

    testWidgets('терминал сўровда бекор қилиш тугмаси йўқ', (t) async {
      await t.pumpWidget(_app(ChinaInquiryDetailScreen(
        inquiry: const ChinaInquiry(
            id: 'i1', refNo: 'CN-0001', status: 'closed', text: 'Samokat 500 dona', quantity: '', quoteCount: 0),
        repository: _FakeRepo(),
      )));
      await t.pumpAndSettle();
      expect(find.text('china_inq_cancel'), findsNothing);
    });
  });
}

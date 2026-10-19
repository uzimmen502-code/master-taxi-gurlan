// Админ панели (эга қарори 2026-10-20): ЎЧИРИШ ўрнига — Хабарлар: «Қайтариб олиш»; Чат: «Архивга олиш»;
// Risk review: ўчириш тугмаси йўқ; шахсий маълумотни ўчириш — фақат superadmin, алоҳида менюда (сабаб + тасдиқ).
// Сервис бу ерда сохта: тасдиқ → тўғри callable (`adminRetractNews` / `adminArchiveSupportChat` / `adminDeleteRecord`)
// тўғри параметр билан чақирилади, бекор → чақирилмайди, хато → қизил snackbar.

import 'package:ava_gurlan/features/admin_web/screens/admin_news_list_screen.dart';
import 'package:ava_gurlan/features/admin_web/screens/chat_support_screen.dart';
import 'package:ava_gurlan/features/admin_web/screens/risk_review_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_auth_service.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_delete_record_service.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_news_read_service.dart';
import 'package:ava_gurlan/features/admin_web/services/support_chat_archive.dart';
import 'package:ava_gurlan/models/chat_message.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/models/risk_event.dart';
import 'package:ava_gurlan/repositories/chat_repository.dart';
import 'package:ava_gurlan/repositories/news_repository.dart';
import 'package:ava_gurlan/repositories/user_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService implements AdminDeleteRecordService {
  final calls = <String>[];
  Object? failWith;
  bool partial = false;

  @override
  Future<bool> retractNews(String id, {String reason = ''}) async {
    calls.add('retract:$id');
    if (failWith != null) throw failWith!;
    return true;
  }

  @override
  Future<bool> archiveSupportChat(String chatId,
      {required bool archived}) async {
    calls.add('archive:$chatId:$archived');
    if (failWith != null) throw failWith!;
    return true;
  }

  @override
  Future<AdminDeleteResult> eraseSupportChat(String chatId,
      {required String reason}) async {
    calls.add('erase:$chatId:$reason');
    if (failWith != null) throw failWith!;
    return AdminDeleteResult(deleted: true, partial: partial);
  }
}

class _FakeUsers implements UserRepository {
  @override
  Stream<List<RiskEvent>> watchOpenRiskEvents({int limit = 200}) =>
      Stream.value(const [
        RiskEvent(
            id: 'r1',
            userId: '998901112233',
            type: 'same_device_new_phone',
            severity: 'high',
            status: 'open',
            message: 'Қурилма бир'),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeNews implements NewsRepository {
  @override
  Stream<List<NewsItem>> watchForAdmin(
          {required bool orderOnly, int limit = 300}) =>
      Stream.value([
        NewsItem(
            id: 'n1',
            title: 'Аксия',
            body: 'Матн',
            createdAt: DateTime(2026, 10, 19, 12)),
        NewsItem(
            id: 'n2',
            title: 'Эски аксия',
            body: 'Матн 2',
            createdAt: DateTime(2026, 10, 18, 12),
            audience: 'retracted',
            retractedAt: DateTime(2026, 10, 19, 13)),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeChats implements ChatRepository {
  @override
  Stream<List<ChatMessage>> watchMessages(String chatId) => Stream.value([
        ChatMessage(
            id: 'm1',
            text: 'Салом',
            fromPhone: chatId,
            createdAt: DateTime(2026, 10, 19, 10)),
        ChatMessage(
            id: 'm2',
            text: 'Жавоб',
            fromAdmin: true,
            createdAt: DateTime(2026, 10, 19, 10, 5)),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAuth extends ChangeNotifier implements AdminAuthService {
  _FakeAuth({this.superAdmin = false});
  final bool superAdmin;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  String? get phoneDigits => '998915000001';

  @override
  String? get phone => '+998915000001';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

const _chat = '998901112233';

void main() {
  late _FakeService svc;
  setUp(() {
    svc = _FakeService();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester t, Widget child,
      {bool superAdmin = false}) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        Provider<AdminDeleteRecordService>.value(value: svc),
        Provider<UserRepository>.value(value: _FakeUsers()),
        Provider<NewsRepository>.value(value: _FakeNews()),
        Provider<ChatRepository>.value(value: _FakeChats()),
        ChangeNotifierProvider<AdminAuthService>.value(
            value: _FakeAuth(superAdmin: superAdmin)),
        ChangeNotifierProvider<AdminNewsReadService>(
            create: (_) => AdminNewsReadService()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await t.pumpAndSettle();
  }

  group('Risk review', () {
    testWidgets('ўчириш тугмаси йўқ, «Resolved» қолган', (t) async {
      await pump(t, const RiskReviewScreen());
      expect(find.byKey(const ValueKey('risk-delete')), findsNothing);
      expect(find.text('Ўчириш'), findsNothing);
      expect(find.text('Resolved'), findsOneWidget);
    });
  });

  group('Хабарлар (admin_news): қайтариб олиш', () {
    testWidgets(
        '«Қайтариб олиш» → тасдиқ матни (барчадан йўқолади, 90 кун) → retract:n1; ўчириш тугмаси йўқ',
        (t) async {
      await pump(t, const AdminNewsListScreen());
      expect(find.byKey(const ValueKey('news-delete-n1')), findsNothing);
      await t.tap(find.byKey(const ValueKey('news-retract-n1')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('барча фойдаланувчилардан йўқолади'),
          findsOneWidget);
      expect(find.textContaining('тарихда 90 кун сақланади'), findsOneWidget);
      expect(svc.calls, isEmpty, reason: 'диалогдан олдин чақирилмайди');
      await t.tap(_inDialog('Қайтариб олиш'));
      await t.pumpAndSettle();
      expect(svc.calls, ['retract:n1']);
      expect(find.textContaining('қайтариб олинди'), findsOneWidget);
    });

    testWidgets('бекор → чақирилмайди', (t) async {
      await pump(t, const AdminNewsListScreen());
      await t.tap(find.byKey(const ValueKey('news-retract-n1')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Бекор'));
      await t.pumpAndSettle();
      expect(svc.calls, isEmpty);
    });

    testWidgets(
        'сервер PERSONAL_NEWS_NOT_RETRACTABLE → тушунарли қизил snackbar',
        (t) async {
      svc.failWith = const AdminDeleteRecordException(
          'failed-precondition', 'PERSONAL_NEWS_NOT_RETRACTABLE', 'x');
      await pump(t, const AdminNewsListScreen());
      await t.tap(find.byKey(const ValueKey('news-retract-n1')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Қайтариб олиш'));
      await t.pumpAndSettle();
      expect(svc.calls, ['retract:n1']);
      expect(find.textContaining('Шахсий ва буюртма хабарларини'),
          findsOneWidget);
    });

    testWidgets(
        'қайтарилган хабар: хира, «Қайтариб олинган» белгиси, тугма ва «Push qayta» йўқ',
        (t) async {
      await pump(t, const AdminNewsListScreen());
      expect(find.byKey(const ValueKey('news-retracted-n2')), findsOneWidget);
      expect(find.text('Қайтариб олинган'), findsOneWidget);
      expect(find.byKey(const ValueKey('news-retract-n2')), findsNothing);
      // faqat n1 uchun «Push qayta»
      expect(find.text('Push qayta'), findsOneWidget);
      final opacities =
          t.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity);
      expect(opacities, contains(0.5));
    });
  });

  group('Чат-қўллаб-қуввaтлаш: архив', () {
    testWidgets('алоҳида хабар/чат ўчириш тугмалари йўқ', (t) async {
      await pump(t, const SupportChatView(chatId: _chat));
      expect(find.byKey(const ValueKey('msg-delete-m1')), findsNothing);
      expect(find.byKey(const ValueKey('msg-delete-m2')), findsNothing);
      expect(find.byKey(const ValueKey('chat-delete')), findsNothing);
      expect(find.byKey(const ValueKey('chat-archive')), findsOneWidget);
      expect(find.text('Архивга олиш'), findsOneWidget);
    });

    testWidgets('«Архивга олиш» → archive:chat:true, танлов тозаланади',
        (t) async {
      var changed = 0;
      await pump(t,
          SupportChatView(chatId: _chat, onArchiveChanged: () => changed++));
      await t.tap(find.byKey(const ValueKey('chat-archive')));
      await t.pumpAndSettle();
      expect(svc.calls, ['archive:$_chat:true']);
      expect(changed, 1);
      expect(find.text('Чат архивга олинди'), findsOneWidget);
    });

    testWidgets('архивдаги чат: «Архивдан чиқариш» → archive:chat:false',
        (t) async {
      await pump(t, const SupportChatView(chatId: _chat, archived: true));
      expect(find.byKey(const ValueKey('chat-archive')), findsNothing);
      await t.tap(find.byKey(const ValueKey('chat-unarchive')));
      await t.pumpAndSettle();
      expect(svc.calls, ['archive:$_chat:false']);
    });

    testWidgets('архивлаш хатоси → «Хатолик» snackbar, танлов қолади',
        (t) async {
      svc.failWith = const AdminDeleteRecordException('internal', '', 'x');
      var changed = 0;
      await pump(t,
          SupportChatView(chatId: _chat, onArchiveChanged: () => changed++));
      await t.tap(find.byKey(const ValueKey('chat-archive')));
      await t.pumpAndSettle();
      expect(changed, 0);
      expect(find.textContaining('Хатoлик'), findsOneWidget);
    });
  });

  group('Шахсий маълумотни ўчириш (фақат superadmin)', () {
    testWidgets('оддий admin меню кўрмайди', (t) async {
      await pump(t, const SupportChatView(chatId: _chat, archived: true));
      expect(find.byKey(const ValueKey('chat-more')), findsNothing);
    });

    testWidgets('superadmin, лекин чат архивда эмас → меню банди ўчирилган',
        (t) async {
      await pump(t, const SupportChatView(chatId: _chat), superAdmin: true);
      await t.tap(find.byKey(const ValueKey('chat-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-erase')),
          warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(svc.calls, isEmpty);
    });

    testWidgets(
        'superadmin + архивда: сабаб <10 белги ёки тасдиқсиз тугма ўчиқ; тўлдирилса → erase:chat:сабаб, танлов тозаланади',
        (t) async {
      var cleared = 0;
      await pump(
          t,
          SupportChatView(
              chatId: _chat, archived: true, onChatDeleted: () => cleared++),
          superAdmin: true);
      await t.tap(find.byKey(const ValueKey('chat-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-erase')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      bool submitEnabled() => t
          .widget<TextButton>(find.byKey(const ValueKey('erase-submit')))
          .onPressed != null;
      expect(submitEnabled(), isFalse);
      await t.enterText(find.byKey(const ValueKey('erase-reason')), 'qisqa');
      await t.tap(find.byKey(const ValueKey('erase-confirm')));
      await t.pumpAndSettle();
      expect(submitEnabled(), isFalse, reason: '5 белги < 10');
      await t.enterText(find.byKey(const ValueKey('erase-reason')),
          'мижоз ёзма талаб қилди');
      await t.pumpAndSettle();
      expect(submitEnabled(), isTrue);
      expect(svc.calls, isEmpty);
      await t.tap(find.byKey(const ValueKey('erase-submit')));
      await t.pumpAndSettle();
      expect(svc.calls, ['erase:$_chat:мижоз ёзма талаб қилди']);
      expect(cleared, 1);
    });

    testWidgets('тасдиқ белгисисиз (сабаб етарли) тугма ўчиқ', (t) async {
      await pump(t, const SupportChatView(chatId: _chat, archived: true),
          superAdmin: true);
      await t.tap(find.byKey(const ValueKey('chat-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-erase')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('erase-reason')),
          'мижоз ёзма талаб қилди');
      await t.pumpAndSettle();
      expect(
          t
              .widget<TextButton>(find.byKey(const ValueKey('erase-submit')))
              .onPressed,
          isNull);
    });

    testWidgets('бекор → чақирилмайди', (t) async {
      await pump(t, const SupportChatView(chatId: _chat, archived: true),
          superAdmin: true);
      await t.tap(find.byKey(const ValueKey('chat-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-erase')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Бекор'));
      await t.pumpAndSettle();
      expect(svc.calls, isEmpty);
    });

    testWidgets('сервер CHAT_NOT_ARCHIVED → тушунарли snackbar, танлов қолади',
        (t) async {
      svc.failWith = const AdminDeleteRecordException(
          'failed-precondition', 'CHAT_NOT_ARCHIVED', 'x');
      var cleared = 0;
      await pump(
          t,
          SupportChatView(
              chatId: _chat, archived: true, onChatDeleted: () => cleared++),
          superAdmin: true);
      await t.tap(find.byKey(const ValueKey('chat-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-erase')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('erase-reason')),
          'мижоз ёзма талаб қилди');
      await t.tap(find.byKey(const ValueKey('erase-confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('erase-submit')));
      await t.pumpAndSettle();
      expect(cleared, 0);
      expect(find.textContaining('Аввал чатни архивга олинг'), findsOneWidget);
    });

    testWidgets('partial (катта чат) → танлов тозаланмайди, "яна босинг"',
        (t) async {
      svc.partial = true;
      var cleared = 0;
      await pump(
          t,
          SupportChatView(
              chatId: _chat, archived: true, onChatDeleted: () => cleared++),
          superAdmin: true);
      await t.tap(find.byKey(const ValueKey('chat-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-erase')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('erase-reason')),
          'мижоз ёзма талаб қилди');
      await t.tap(find.byKey(const ValueKey('erase-confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('erase-submit')));
      await t.pumpAndSettle();
      expect(cleared, 0);
      expect(find.textContaining('яна босинг'), findsOneWidget);
    });
  });

  group('isSupportChatArchived (рўйхат филтри ва badge қоидаси)', () {
    Timestamp ts(int ms) => Timestamp.fromMillisecondsSinceEpoch(ms);

    test('архив белгиси йўқ → архивда эмас', () {
      expect(isSupportChatArchived({}), isFalse);
      expect(isSupportChatArchived({'updatedAt': ts(5)}), isFalse);
    });

    test('adminArchivedAt бор ва updatedAt ундан кейин эмас → архивда', () {
      expect(isSupportChatArchived({'adminArchivedAt': ts(100)}), isTrue);
      expect(
          isSupportChatArchived(
              {'adminArchivedAt': ts(100), 'updatedAt': ts(50)}),
          isTrue);
      expect(
          isSupportChatArchived(
              {'adminArchivedAt': ts(100), 'updatedAt': ts(100)}),
          isTrue);
    });

    test('архивдан КЕЙИН янги хабар (updatedAt ошди) → чат қайта очилади', () {
      expect(
          isSupportChatArchived(
              {'adminArchivedAt': ts(100), 'updatedAt': ts(101)}),
          isFalse);
    });
  });
}

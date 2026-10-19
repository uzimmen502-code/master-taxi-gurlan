// Админ панели «Ўчириш» тугмалари (2026-10-19): Risk review, Хабарлар, Чат-қўллаб-қуввaтлаш (хабар ва бутун чат).
// Ўчириш СЕРВЕР callable'и (`adminDeleteRecord`) орқали — бу ерда сохта сервис: тасдиқ → тўғри kind/id билан чақирилади,
// бекор → чақирилмайди, хато → қизил snackbar.

import 'package:ava_gurlan/features/admin_web/screens/admin_news_list_screen.dart';
import 'package:ava_gurlan/features/admin_web/screens/chat_support_screen.dart';
import 'package:ava_gurlan/features/admin_web/screens/risk_review_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_auth_service.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_delete_record_service.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_news_read_service.dart';
import 'package:ava_gurlan/models/chat_message.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/models/risk_event.dart';
import 'package:ava_gurlan/repositories/chat_repository.dart';
import 'package:ava_gurlan/repositories/news_repository.dart';
import 'package:ava_gurlan/repositories/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDelete implements AdminDeleteRecordService {
  final calls = <String>[];
  Object? failWith;
  bool partial = false;

  Future<AdminDeleteResult> _rec(String c) async {
    calls.add(c);
    if (failWith != null) throw failWith!;
    return AdminDeleteResult(deleted: true, partial: partial);
  }

  @override
  Future<AdminDeleteResult> deleteRiskEvent(String id, {String reason = ''}) =>
      _rec('risk_event:$id');

  @override
  Future<AdminDeleteResult> deleteNews(String id, {String reason = ''}) =>
      _rec('admin_news:$id');

  @override
  Future<AdminDeleteResult> deleteSupportMessage(
          String chatId, String messageId,
          {String reason = ''}) =>
      _rec('support_message:$chatId:$messageId');

  @override
  Future<AdminDeleteResult> deleteSupportChat(String chatId,
          {String reason = ''}) =>
      _rec('support_chat:$chatId');
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
            createdAt: DateTime(2026, 10, 19, 12))
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

void main() {
  late _FakeDelete del;
  setUp(() {
    del = _FakeDelete();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        Provider<AdminDeleteRecordService>.value(value: del),
        Provider<UserRepository>.value(value: _FakeUsers()),
        Provider<NewsRepository>.value(value: _FakeNews()),
        Provider<ChatRepository>.value(value: _FakeChats()),
        ChangeNotifierProvider<AdminAuthService>.value(value: _FakeAuth()),
        ChangeNotifierProvider<AdminNewsReadService>(
            create: (_) => AdminNewsReadService()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await t.pumpAndSettle();
  }

  group('Risk review', () {
    testWidgets(
        '«Ўчириш» → тасдиқ → risk_event:r1 чақирилади, муваффақият snackbar',
        (t) async {
      await pump(t, const RiskReviewScreen());
      await t.tap(find.byKey(const ValueKey('risk-delete')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('қайтариб бўлмайди'), findsOneWidget);
      expect(find.textContaining('audit'), findsOneWidget);
      expect(del.calls, isEmpty, reason: 'диалогдан олдин чақирилмайди');
      await t.tap(_inDialog('Ўчириш'));
      await t.pumpAndSettle();
      expect(del.calls, ['risk_event:r1']);
      expect(find.text('Risk event ўчирилди'), findsOneWidget);
    });

    testWidgets('бекор → чақирилмайди', (t) async {
      await pump(t, const RiskReviewScreen());
      await t.tap(find.byKey(const ValueKey('risk-delete')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Бекор'));
      await t.pumpAndSettle();
      expect(del.calls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('сервер хатоси → «Хатолик» snackbar', (t) async {
      del.failWith = const AdminDeleteRecordException(
          'permission-denied', '', 'Фақат админ');
      await pump(t, const RiskReviewScreen());
      await t.tap(find.byKey(const ValueKey('risk-delete')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Ўчириш'));
      await t.pumpAndSettle();
      expect(del.calls, ['risk_event:r1']);
      expect(find.textContaining('Хатолик'), findsOneWidget);
    });
  });

  group('Хабарлар (admin_news)', () {
    testWidgets(
        'карточкадаги ўчириш → тасдиқ → admin_news:n1 (callable, тўғридан-тўғри delete эмас)',
        (t) async {
      await pump(t, const AdminNewsListScreen());
      await t.tap(find.byKey(const ValueKey('news-delete-n1')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(del.calls, isEmpty);
      await t.tap(_inDialog('Ўчириш'));
      await t.pumpAndSettle();
      expect(del.calls, ['admin_news:n1']);
    });

    testWidgets('бекор → чақирилмайди', (t) async {
      await pump(t, const AdminNewsListScreen());
      await t.tap(find.byKey(const ValueKey('news-delete-n1')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Бекор'));
      await t.pumpAndSettle();
      expect(del.calls, isEmpty);
    });
  });

  group('Чат-қўллаб-қуввaтлаш', () {
    testWidgets('хабар ўчириш → тасдиқ → support_message:chat:m1', (t) async {
      await pump(t, const SupportChatView(chatId: '998901112233'));
      await t.tap(find.byKey(const ValueKey('msg-delete-m1')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(_inDialog('Ўчириш'));
      await t.pumpAndSettle();
      expect(del.calls, ['support_message:998901112233:m1']);
      expect(find.text('Хабар ўчирилди'), findsOneWidget);
    });

    testWidgets('хабар ўчириш бекор → чақирилмайди', (t) async {
      await pump(t, const SupportChatView(chatId: '998901112233'));
      await t.tap(find.byKey(const ValueKey('msg-delete-m2')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Бекор'));
      await t.pumpAndSettle();
      expect(del.calls, isEmpty);
    });

    testWidgets(
        'чатни ўчириш → тасдиқ → support_chat:chat, танлов тозаланади (onChatDeleted)',
        (t) async {
      var cleared = 0;
      await pump(
          t,
          SupportChatView(
              chatId: '998901112233', onChatDeleted: () => cleared++));
      await t.tap(find.byKey(const ValueKey('chat-delete')));
      await t.pumpAndSettle();
      expect(find.textContaining('мижоз'), findsWidgets);
      await t.tap(_inDialog('Ўчириш'));
      await t.pumpAndSettle();
      expect(del.calls, ['support_chat:998901112233']);
      expect(cleared, 1);
    });

    testWidgets('чатни ўчириш бекор → чақирилмайди, танлов қолади', (t) async {
      var cleared = 0;
      await pump(
          t,
          SupportChatView(
              chatId: '998901112233', onChatDeleted: () => cleared++));
      await t.tap(find.byKey(const ValueKey('chat-delete')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Бекор'));
      await t.pumpAndSettle();
      expect(del.calls, isEmpty);
      expect(cleared, 0);
    });

    testWidgets(
        'partial (катта чат) → танлов тозаланмайди, "яна босинг" огоҳлантириши',
        (t) async {
      del.partial = true;
      var cleared = 0;
      await pump(
          t,
          SupportChatView(
              chatId: '998901112233', onChatDeleted: () => cleared++));
      await t.tap(find.byKey(const ValueKey('chat-delete')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Ўчириш'));
      await t.pumpAndSettle();
      expect(del.calls, ['support_chat:998901112233']);
      expect(cleared, 0);
      expect(find.textContaining('яна босинг'), findsOneWidget);
    });

    testWidgets('чат ўчириш хатоси → «Хатолик» snackbar, танлов қолади',
        (t) async {
      del.failWith =
          const AdminDeleteRecordException('internal', 'DELETE_FAILED', 'x');
      var cleared = 0;
      await pump(
          t,
          SupportChatView(
              chatId: '998901112233', onChatDeleted: () => cleared++));
      await t.tap(find.byKey(const ValueKey('chat-delete')));
      await t.pumpAndSettle();
      await t.tap(_inDialog('Ўчириш'));
      await t.pumpAndSettle();
      expect(cleared, 0);
      expect(find.textContaining('Хатoлик'), findsOneWidget);
    });
  });
}

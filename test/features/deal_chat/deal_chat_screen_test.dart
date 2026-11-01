// «Буюртма ёзиш» чати — экран (fake репозиторий, Firebase'сиз): маҳсулот сарлавҳаси, юбориш
// оқими, хатода матн сақланиши ва ШУ clientId билан қайта юбориш, ўқилди белгиси, рўйхат
// қатори (ўқилмаганлар), push юкламаси ва олд режимдаги push'ни яшириш.
import 'dart:async';

import 'package:ava_gurlan/features/chat/widgets/message_bubble.dart';
import 'package:ava_gurlan/features/deal_chat/data/deal_chat_repository.dart';
import 'package:ava_gurlan/features/deal_chat/deal_chat_support.dart';
import 'package:ava_gurlan/features/deal_chat/open_deal_chat.dart';
import 'package:ava_gurlan/features/deal_chat/screens/deal_chat_screen.dart';
import 'package:ava_gurlan/features/deal_chat/screens/deal_chats_screen.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_channel_contact_bar.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

const buyer = '998901110001';
const seller = '998901110002';
const chatId = 'p1_$buyer';

class FakeDealRepo implements DealChatRepository {
  final chat = StreamController<DealChat?>.broadcast();
  final messages = StreamController<List<DealMessage>>.broadcast();
  final sent = <Map<String, String>>[];
  final readCalls = <String>[];
  Object? failNextSend;
  Completer<void>? sendGate;

  @override
  Stream<DealChat?> watchChat(String id) => chat.stream;
  @override
  Stream<List<DealMessage>> watchMessages(String id, {int limit = 200}) => messages.stream;
  @override
  Future<void> send({required String chatId, required String text, required String clientId}) async {
    sent.add({'chatId': chatId, 'text': text, 'clientId': clientId});
    if (sendGate != null) await sendGate!.future;
    final f = failNextSend;
    if (f != null) {
      failNextSend = null;
      throw f;
    }
  }

  @override
  Future<void> markRead(String id) async => readCalls.add(id);
  final fetchCalls = <String>[];
  @override
  Future<WholesaleProduct?> fetchProduct(String productId) async {
    fetchCalls.add(productId);
    return null;
  }
  final openCalls = <(String, String)>[];
  @override
  Future<String> openChat(String productId, {String source = 'wholesale'}) async {
    openCalls.add((productId, source));
    return 'p1_$buyer';
  }
  @override
  Stream<List<DealChat>> watchMyChats(String myUid, {int limit = 50}) => const Stream.empty();
  @override
  Stream<int> watchUnreadTotal(String myUid) => const Stream.empty();
}

DealChat chatDoc({Map<String, int> unread = const {}, String lastFrom = buyer, String last = 'salom'}) =>
    DealChat(
      id: chatId,
      members: const [buyer, seller],
      buyerId: buyer,
      sellerId: seller,
      productId: 'p1',
      productTitle: 'Samokat X1',
      lastMessage: last,
      lastFrom: lastFrom,
      lastAt: DateTime(2026, 11, 1, 9, 5),
      unread: unread,
    );

final product = WholesaleProduct(
  id: 'p1',
  sellerId: seller,
  sellerCompanyName: 'Sunlight',
  title: 'Samokat X1',
  titleLower: 'samokat x1',
  description: 'd',
  priceTiers: const [WholesalePriceTier(minQty: 1, price: 45000)],
);

void main() {
  final d = JsonL10nDelegate();

  Future<FakeDealRepo> pumpChat(WidgetTester tester, {String me = buyer, WholesaleProduct? p}) async {
    final repo = FakeDealRepo();
    await tester.pumpWidget(l10nApp(
      delegate: d,
      home: DealChatScreen(chatId: chatId, myUid: me, repository: repo, initialProduct: p),
    ));
    repo.chat.add(chatDoc());
    repo.messages.add(const []);
    await tester.pump();
    return repo;
  }

  testWidgets('сарлавҳа: маҳсулот номи ва нархи; хабар йўқ — бўш ҳолат; харидорга «Сотувчи билан чат»',
      (tester) async {
    await pumpChat(tester, p: product);
    expect(find.text('Samokat X1'), findsOneWidget);
    expect(find.byKey(const ValueKey('deal-chat-price')), findsOneWidget);
    expect(find.textContaining('45'), findsWidgets);
    expect(find.byKey(const ValueKey('deal-chat-empty')), findsOneWidget);
    expect(find.text(d.tr('deal_chat_with_seller')), findsOneWidget);
    expect(DealChatPresence.openChatId, chatId);
  });

  testWidgets('сотувчи учун сарлавҳа «Харидор билан чат»; ёпилганда presence тозаланади', (tester) async {
    await pumpChat(tester, me: seller);
    expect(find.text(d.tr('deal_chat_with_buyer')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(DealChatPresence.openChatId, isNull);
  });

  testWidgets('юбориш: trim, clientId шакли, майдон тозаланади; сервер хабари пуфакчада (меники ўнгда)',
      (tester) async {
    final repo = await pumpChat(tester);
    await tester.enterText(find.byKey(const ValueKey('deal-chat-input')), '  100 dona kerak  ');
    await tester.tap(find.byKey(const ValueKey('deal-chat-send')));
    await tester.pump();
    expect(repo.sent.length, 1);
    expect(repo.sent.single['text'], '100 dona kerak');
    expect(repo.sent.single['chatId'], chatId);
    expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(repo.sent.single['clientId']!), isTrue);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('deal-chat-input'))).controller!.text, '');

    repo.messages.add([
      DealMessage(id: 'm1', from: buyer, text: '100 dona kerak', at: DateTime(2026, 11, 1, 9)),
      DealMessage(id: 'm2', from: seller, text: 'Dona 45 000', at: DateTime(2026, 11, 1, 9, 1)),
    ]);
    await tester.pump();
    final mine = tester.widget<MessageBubble>(find.byKey(const ValueKey('deal-msg-m1')));
    final theirs = tester.widget<MessageBubble>(find.byKey(const ValueKey('deal-msg-m2')));
    expect([mine.isMine, theirs.isMine], [true, false]);
    // Умумий пуфакча: «Админ» ёрлиғи чиқмайди.
    expect(find.text(d.tr('chat_admin_label')), findsNothing);
  });

  testWidgets('бўш/фақат бўшлиқ матн — юборилмайди', (tester) async {
    final repo = await pumpChat(tester);
    await tester.enterText(find.byKey(const ValueKey('deal-chat-input')), '    ');
    await tester.tap(find.byKey(const ValueKey('deal-chat-send')));
    await tester.pump();
    expect(repo.sent, isEmpty);
  });

  testWidgets('хато (RATE_LIMITED): матн майдонга қайтади, тушунарли хабар; қайта юбориш — ШУ clientId',
      (tester) async {
    final repo = await pumpChat(tester);
    repo.failNextSend = FirebaseFunctionsException(code: 'resource-exhausted', message: 'RATE_LIMITED');
    await tester.enterText(find.byKey(const ValueKey('deal-chat-input')), 'Narxi?');
    await tester.tap(find.byKey(const ValueKey('deal-chat-send')));
    await tester.pump();
    await tester.pump();
    expect(find.text(d.tr('err_too_many')), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byKey(const ValueKey('deal-chat-input'))).controller!.text, 'Narxi?');
    await tester.tap(find.byKey(const ValueKey('deal-chat-send')));
    await tester.pump();
    expect(repo.sent.length, 2);
    expect(repo.sent[1]['clientId'], repo.sent[0]['clientId']);
    // Бошқа матн — янги clientId.
    await tester.enterText(find.byKey(const ValueKey('deal-chat-input')), 'Yana bir savol');
    await tester.tap(find.byKey(const ValueKey('deal-chat-send')));
    await tester.pump();
    expect(repo.sent[2]['clientId'], isNot(repo.sent[0]['clientId']));
  });

  testWidgets('юборилаётганда тугма ўчиқ (иккинчи босиш иккинчи хабар бермайди)', (tester) async {
    final repo = await pumpChat(tester);
    repo.sendGate = Completer<void>();
    await tester.enterText(find.byKey(const ValueKey('deal-chat-input')), 'bir');
    await tester.tap(find.byKey(const ValueKey('deal-chat-send')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('deal-chat-send')));
    await tester.pump();
    expect(repo.sent.length, 1);
    repo.sendGate!.complete();
    await tester.pump();
  });

  testWidgets('ўқилди: менинг unread > 0 бўлса markRead; 0 бўлса чақирилмайди', (tester) async {
    final repo = await pumpChat(tester);
    expect(repo.readCalls, isEmpty);
    repo.chat.add(chatDoc(unread: {buyer: 2, seller: 0}));
    await tester.pump();
    expect(repo.readCalls, [chatId]);
    repo.chat.add(chatDoc(unread: {buyer: 0, seller: 3}));
    await tester.pump();
    expect(repo.readCalls.length, 1);
  });

  testWidgets('рўйхат қатори: қарши томон, «Сиз:» префикси, ўқилмаганлар нишони', (tester) async {
    await tester.pumpWidget(l10nApp(
      delegate: d,
      home: Scaffold(
        body: Column(children: [
          DealChatTile(chat: chatDoc(unread: {seller: 3}), myUid: seller, onTap: () {}),
          DealChatTile(chat: chatDoc(lastFrom: buyer, last: 'salom'), myUid: buyer, onTap: () {}),
        ]),
      ),
    ));
    expect(find.text(d.tr('deal_chat_role_buyer')), findsOneWidget); // сотувчи кўради: харидор
    expect(find.text(d.tr('deal_chat_role_seller')), findsOneWidget); // харидор кўради: сотувчи
    expect(find.text('3'), findsOneWidget);
    expect(find.text('${d.tr('deal_chat_you')} salom'), findsOneWidget);
  });

  test('push юкламаси: фақат deal_chat ва сервер шаклидаги chatId', () {
    expect(dealChatIdFromPush({'type': 'deal_chat', 'chatId': chatId}), chatId);
    expect(dealChatIdFromPush({'screen': 'deal_chat', 'chatId': chatId}), chatId);
    expect(dealChatIdFromPush({'type': 'support_chat', 'chatId': chatId}), isNull);
    expect(dealChatIdFromPush({'type': 'deal_chat', 'chatId': '../x'}), isNull);
    expect(dealChatIdFromPush({'type': 'deal_chat', 'chatId': 'p1_123'}), isNull);
    expect(dealChatIdFromPush({'type': 'deal_chat'}), isNull);
  });

  test('олд режим push: фақат ОЧИҚ чат учун яширилади', () {
    DealChatPresence.enter(chatId);
    expect(DealChatPresence.suppressForeground({'type': 'deal_chat', 'chatId': chatId}), isTrue);
    expect(DealChatPresence.suppressForeground({'type': 'deal_chat', 'chatId': 'p2_$buyer'}), isFalse);
    expect(DealChatPresence.suppressForeground({'type': 'order', 'chatId': chatId}), isFalse);
    DealChatPresence.leave(chatId);
    expect(DealChatPresence.suppressForeground({'type': 'deal_chat', 'chatId': chatId}), isFalse);
  });

  test('сервер хато кодлари → калитлар (3 тилда мавжуд)', () {
    for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = loadLang(lang);
      for (final k in kDealChatServerErrors.values) {
        expect(m.containsKey(k), isTrue, reason: '$lang:$k');
      }
    }
  });

  test('бош саҳифа белгиси: фақат МЕНИНГ ўқилмаганларим қўшилади', () {
    final chats = [
      chatDoc(unread: {seller: 3, buyer: 1}),
      chatDoc(unread: {seller: 2}),
      chatDoc(unread: const {}),
    ];
    expect(DealChatRepository.sumUnread(chats, seller), 5);
    expect(DealChatRepository.sumUnread(chats, buyer), 1);
    expect(DealChatRepository.sumUnread(const [], seller), 0);
  });

  test('clientId: сервер шакли, ҳар сафар янги', () {
    final a = DealChatRepository.newClientId();
    final b = DealChatRepository.newClientId();
    expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(a), isTrue);
    expect(a, isNot(b));
  });
  group('Аралаш бозор «Ёзиш» (эга 2026-11-01)', () {
    test('DealChat: source/productPrice; эски ҳужжат (майдонсиз) — wholesale, нарх йўқ', () {
      final a = DealChat.fromMap('ad-a1_$buyer', {
        'members': [buyer, seller], 'buyerId': buyer, 'sellerId': seller, 'productId': 'a1',
        'source': 'ad', 'market': 'aralash', 'productPrice': 450000,
      });
      expect([a.source, a.market, a.productPrice], ['ad', 'aralash', 450000]);
      final old = DealChat.fromMap(chatId, {'members': [buyer, seller], 'productId': 'p1'});
      expect([old.source, old.productPrice], ['wholesale', null]);
      final bad = DealChat.fromMap(chatId, {'productPrice': 10.5});
      expect(bad.productPrice, isNull, reason: 'пул — фақат бутун сон');
    });

    testWidgets('Аралаш чат: нарх чатдан (сўм), Улгуржи маҳсулоти ЎҚИЛМАЙДИ', (tester) async {
      final repo = FakeDealRepo();
      await tester.pumpWidget(l10nApp(delegate: d, home: DealChatScreen(chatId: 'ad-a1_$buyer', myUid: buyer, repository: repo)));
      repo.chat.add(const DealChat(
        id: 'ad-a1_$buyer', members: [buyer, seller], buyerId: buyer, sellerId: seller, productId: 'a1',
        source: 'ad', market: 'aralash', productPrice: 450000, productTitle: 'Velosiped',
      ));
      repo.messages.add(const []);
      await tester.pump();
      expect(find.text('Velosiped'), findsOneWidget);
      final price = tester.widget<Text>(find.byKey(const ValueKey('deal-chat-price'))).data!;
      expect(price, contains('450'));
      expect(price, contains(d.tr('currency_sum')));
      expect(repo.fetchCalls, isEmpty);
    });

    testWidgets('Улгуржи чат (source йўқ) — маҳсулот аввалгидек ўқилади', (tester) async {
      final repo = await pumpChat(tester);
      expect(repo.fetchCalls, ['p1']);
    });

    test('«Ёзиш» кўриниши: ўз эълонида йўқ, меҳмонга бор, эгасиз — йўқ; рақам шакли фарқ қилмайди', () {
      expect(dealChatShowWrite(myUid: buyer, ownerPhone: seller), isTrue);
      expect(dealChatShowWrite(myUid: seller, ownerPhone: '+998 90 111 00 02'), isFalse);
      expect(dealChatShowWrite(myUid: seller, ownerPhone: '901110002'), isFalse);
      expect(dealChatShowWrite(myUid: '', ownerPhone: seller), isTrue);
      expect(dealChatShowWrite(myUid: buyer, ownerPhone: ''), isFalse);
    });

    test('push: ad-/si- префиксли чат ID ҳам қабул қилинади', () {
      expect(dealChatIdFromPush({'type': 'deal_chat', 'chatId': 'ad-AbC123_$buyer'}), 'ad-AbC123_$buyer');
      expect(dealChatIdFromPush({'type': 'deal_chat', 'chatId': 'si-NaN_$buyer'}), 'si-NaN_$buyer');
    });

    testWidgets('дўкон маҳсулоти пастки панели: onWrite берилса «Ёзиш» бор ва ишлайди; йўқ — фақат қўнғироқ', (tester) async {
      var writes = 0;
      await tester.pumpWidget(l10nApp(delegate: d, home: Scaffold(bottomNavigationBar: TvChannelContactBar(onCall: () {}, onWrite: () => writes++))));
      await tester.pump();
      expect(find.text(d.tr('deal_chat_write')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('contact_bar_write')));
      expect(writes, 1);
      await tester.pumpWidget(l10nApp(delegate: d, home: Scaffold(bottomNavigationBar: TvChannelContactBar(onCall: () {}))));
      await tester.pump();
      expect(find.byKey(const ValueKey('contact_bar_write')), findsNothing);
      await tester.pumpWidget(l10nApp(delegate: d, home: Scaffold(bottomNavigationBar: TvChannelContactBar(onCall: () {}, onWrite: () => writes++, writeBusy: true))));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('contact_bar_write')), warnIfMissed: false);
      expect(writes, 1, reason: 'band пайтида иккинчи босиш йўқ');
    });

    testWidgets('меҳмон «Ёзиш» босса — сервер чақирилмайди, рўйхатдан ўтишга чақирилади', (tester) async {
      final repo = FakeDealRepo();
      await tester.pumpWidget(l10nApp(delegate: d, home: Builder(
        builder: (ctx) => Scaffold(body: TextButton(
          onPressed: () => openDealChatFlow(ctx, productId: 'a1', myUid: '', source: DealChatSource.ad, repository: repo),
          child: const Text('go'),
        )),
      )));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text(d.tr('deal_chat_login_required')), findsOneWidget);
      expect(repo.openCalls, isEmpty);
    });

    testWidgets('рўйхатдан ўтган: манба серверга узатилади ва чат очилади', (tester) async {
      final repo = FakeDealRepo();
      await tester.pumpWidget(l10nApp(delegate: d, home: Builder(
        builder: (ctx) => Scaffold(body: TextButton(
          onPressed: () => openDealChatFlow(ctx, productId: 's1', myUid: buyer, source: DealChatSource.shopItem, repository: repo),
          child: const Text('go'),
        )),
      )));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      expect(repo.openCalls, [('s1', 'shop_item')]);
      expect(find.byType(DealChatScreen), findsOneWidget);
    });
  });
}

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../wholesale/models/wholesale_product.dart';

/// Улгуржи/Хитой «Буюртма ёзиш» чати (эга қарори 2026-11-01) — мижоз томони.
///
/// Сервер: `functions/deal_chats.js` (openDealChat / sendDealMessage / markDealChatRead).
/// Ёзув ФАҚАТ callable орқали (rules'да client-write ёпиқ); ўқиш — фақат иштирокчилар
/// (`members array-contains <ўз рақами>`).
class DealChatRepository {
  DealChatRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore,
        _functions = functions;

  // Лазй: Firebase инициализациясиз (виджет тестларда) обуна яратилмайди.
  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _chats => _db.collection('deal_chats');

  /// Чатни очади ёки мавжудини қайтаради (сервер идемпотент). → `chatId`.
  /// [source]: `wholesale` (Улгуржи/Хитой) | `ad` | `shop_item` (Аралаш бозор) | `business` (объект,
  /// [productId] = объект ID).
  Future<String> openChat(String productId, {String source = 'wholesale'}) async {
    final res = await _fns.httpsCallable('openDealChat').call<Object?>({
      'productId': productId,
      if (source != 'wholesale') 'source': source,
    });
    final d = res.data;
    final id = d is Map ? '${d['chatId'] ?? ''}' : '';
    if (id.isEmpty) throw StateError('openDealChat: chatId missing');
    return id;
  }

  /// Хабар юбориш. [clientId] — қайта уринишда АЙНАН шу (идемпотент).
  Future<void> send({required String chatId, required String text, required String clientId}) async {
    await _fns.httpsCallable('sendDealMessage').call<Object?>({
      'chatId': chatId,
      'text': text,
      'clientId': clientId,
    });
  }

  Future<void> markRead(String chatId) async {
    await _fns.httpsCallable('markDealChatRead').call<Object?>({'chatId': chatId});
  }

  /// Менинг чатларим (харидор ҳам, сотувчи ҳам) — энг янги хабар биринчи. Хабарсиз чат
  /// (`lastAt` йўқ) сўровга тушмайди.
  Stream<List<DealChat>> watchMyChats(String myUid, {int limit = 50}) => _chats
      .where('members', arrayContains: myUid)
      .orderBy('lastAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => DealChat.fromMap(d.id, d.data())).toList());

  /// Бош саҳифа «Хабарлар» белгиси учун: менинг ўқилмаган хабарларим йиғиндиси
  /// ([watchMyChats] — энг янги 50 чат; эскироқ чатдаги ўқилмаган белгига тушмайди).
  /// Сон ўзгармаса қайта чиқарилмайди (ортиқча rebuild йўқ).
  Stream<int> watchUnreadTotal(String myUid) =>
      watchMyChats(myUid).map((list) => sumUnread(list, myUid)).distinct();

  static int sumUnread(List<DealChat> chats, String myUid) =>
      chats.fold<int>(0, (s, c) => s + c.unreadFor(myUid));

  Stream<DealChat?> watchChat(String chatId) => _chats
      .doc(chatId)
      .snapshots()
      .map((s) => s.exists ? DealChat.fromMap(s.id, s.data() ?? const {}) : null);

  /// Охирги [limit] хабар, вақт бўйича ўсиб борувчи тартибда.
  Stream<List<DealMessage>> watchMessages(String chatId, {int limit = 200}) => _chats
      .doc(chatId)
      .collection('messages')
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => DealMessage.fromMap(d.id, d.data())).toList().reversed.toList());

  /// Сарлавҳадаги нарх учун. Маҳсулот ўчирилган/ёпиқ бўлса — `null` (чат ишлайверади).
  Future<WholesaleProduct?> fetchProduct(String productId) async {
    if (productId.isEmpty) return null;
    try {
      final snap = await _db.collection('wholesale_products').doc(productId).get();
      return snap.exists ? WholesaleProduct.fromFirestore(snap) : null;
    } catch (_) {
      return null;
    }
  }

  static final Random _rnd = Random.secure();

  /// Сервер шакли: `^[A-Za-z0-9_-]{8,64}$`.
  static String newClientId() {
    const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = List.generate(12, (_) => abc[_rnd.nextInt(abc.length)]).join();
    return 'c${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$r';
  }
}

/// `deal_chats/{chatId}`.
class DealChat {
  const DealChat({
    required this.id,
    required this.members,
    required this.buyerId,
    required this.sellerId,
    required this.productId,
    this.market = 'wholesale',
    this.source = 'wholesale',
    this.productPrice,
    this.productTitle = '',
    this.productPhoto = '',
    this.lastMessage = '',
    this.lastFrom = '',
    this.lastAt,
    this.unread = const {},
    this.businessId = '',
    this.sellerName = '',
  });

  final String id;
  final List<String> members;
  final String buyerId;
  final String sellerId;
  final String productId;
  final String market;

  /// `wholesale` | `ad` | `shop_item`; эски чатларда майдон йўқ — `wholesale`.
  final String source;

  /// Аралаш бозор: чат очилгандаги нарх (сўм, бутун сон); Улгуржида — `null` (нарх маҳсулотдан).
  final int? productPrice;
  final String productTitle;
  final String productPhoto;
  final String lastMessage;
  final String lastFrom;
  final DateTime? lastAt;
  final Map<String, int> unread;

  /// Объект («Менинг бизнесим»): `business` чатида — объектнинг ўзи, `shop_item` чатида — маҳсулот
  /// тегишли объект. Эски чатларда майдон йўқ — `''`.
  final String businessId;

  /// Сотувчи номи (объект номи) — сервер бор бўлса ёзади; йўқ — `''`.
  final String sellerName;

  /// Объект билан чат (маҳсулот эмас): нарх йўқ, сарлавҳада объект номи.
  bool get isBusiness => source == 'business';

  int unreadFor(String uid) => unread[uid] ?? 0;
  bool isSeller(String uid) => sellerId == uid;

  factory DealChat.fromMap(String id, Map<String, dynamic> d) {
    final rawUnread = d['unread'];
    final unread = <String, int>{};
    if (rawUnread is Map) {
      rawUnread.forEach((k, v) {
        if (v is num) unread['$k'] = v.toInt();
      });
    }
    return DealChat(
      id: id,
      members: List<String>.from((d['members'] as List?)?.map((e) => '$e') ?? const <String>[]),
      buyerId: '${d['buyerId'] ?? ''}',
      sellerId: '${d['sellerId'] ?? ''}',
      productId: '${d['productId'] ?? ''}',
      market: '${d['market'] ?? 'wholesale'}',
      source: '${d['source'] ?? 'wholesale'}',
      productPrice: d['productPrice'] is int ? d['productPrice'] as int : null,
      productTitle: '${d['productTitle'] ?? ''}',
      productPhoto: '${d['productPhoto'] ?? ''}',
      lastMessage: '${d['lastMessage'] ?? ''}',
      lastFrom: '${d['lastFrom'] ?? ''}',
      lastAt: (d['lastAt'] is Timestamp) ? (d['lastAt'] as Timestamp).toDate() : null,
      unread: unread,
      businessId: d['businessId'] is String ? (d['businessId'] as String).trim() : '',
      sellerName: d['sellerName'] is String ? (d['sellerName'] as String).trim() : '',
    );
  }
}

/// `deal_chats/{chatId}/messages/{id}`.
class DealMessage {
  const DealMessage({required this.id, required this.from, required this.text, this.at});

  final String id;
  final String from;
  final String text;
  final DateTime? at;

  factory DealMessage.fromMap(String id, Map<String, dynamic> d) => DealMessage(
        id: id,
        from: '${d['from'] ?? ''}',
        text: '${d['text'] ?? ''}',
        at: (d['at'] is Timestamp) ? (d['at'] as Timestamp).toDate() : null,
      );
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart' show canonicalPhoneId, phonesMatch;
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../../tv_market/widgets/shop_complaint_sheet.dart';
import '../data/content_complaint_repository.dart';

/// Сабаб кодлари — сервердаги `REASONS` (functions/content_complaints.js) билан бир хил (PROPOSED, эга тасдиғигача).
/// `other` — изоҳ сўралади (3…300).
const contentComplaintReasons = <ComplaintReason>[
  (value: 'fraud', labelKey: 'content_report_reason_fraud', needsComment: false),
  (value: 'wrong_info', labelKey: 'content_report_reason_wrong_info', needsComment: false),
  (value: 'spam', labelKey: 'ad_report_reason_spam', needsComment: false),
  (value: 'abuse', labelKey: 'ad_report_reason_abuse', needsComment: false),
  (value: 'other', labelKey: 'content_report_reason_other', needsComment: true),
];

typedef ContentComplaintSubmit = Future<void> Function({
  required String targetType,
  required String targetId,
  String restaurantId,
  required String reason,
  String comment,
});

/// «Шикоят қилиш» — ресторан (маълумот варағи), таом варағи ва кўчмас мулк эълони учун ЯГОНА кириш.
///
/// Эга/аъзога кўрсатилмайди ([isMine] — аниқлангунча тугма йўқ). Бу фақат қулайлик: сервер ҳам барибир
/// `COMPLAINT_OWN` билан рад этади (18-банд). Варақ — мавжуд умумий шикоят варағи ([showComplaintSheet]).
/// [closeSheetFirst] — тугма пастки варақ ичида бўлса, аввал у ёпилади (натижа SnackBar'и варақ остида қолмасин).
class ContentComplaintButton extends StatefulWidget {
  const ContentComplaintButton({
    super.key,
    required this.targetType,
    required this.targetId,
    this.restaurantId = '',
    required this.isMine,
    this.closeSheetFirst = false,
    this.submit,
  });

  /// Ресторан ёки уй ошпази (битта модул).
  factory ContentComplaintButton.restaurant({
    Key? key,
    required Restaurant restaurant,
    bool closeSheetFirst = false,
    Future<bool> Function()? isMine,
    ContentComplaintSubmit? submit,
  }) =>
      ContentComplaintButton(
        key: key ?? const ValueKey('content_report_restaurant'),
        targetType: 'restaurant',
        targetId: restaurant.id,
        restaurantId: restaurant.id,
        isMine: isMine ?? () => restaurantIsMine(restaurant),
        closeSheetFirst: closeSheetFirst,
        submit: submit,
      );

  factory ContentComplaintButton.dish({
    Key? key,
    required Restaurant restaurant,
    required MenuItem item,
    bool closeSheetFirst = false,
    Future<bool> Function()? isMine,
    ContentComplaintSubmit? submit,
  }) =>
      ContentComplaintButton(
        key: key ?? const ValueKey('content_report_dish'),
        targetType: 'restaurant_item',
        targetId: item.id,
        restaurantId: restaurant.id,
        isMine: isMine ?? () => restaurantIsMine(restaurant),
        closeSheetFirst: closeSheetFirst,
        submit: submit,
      );

  /// [ownerKeyLoader] — жорий фойдаланувчининг `realtyOwnerKey`и (одатда экраннинг `RealtyRepository.myOwnerKey`).
  factory ContentComplaintButton.realty({
    Key? key,
    required RealtyListing listing,
    Future<String> Function()? ownerKeyLoader,
    ContentComplaintSubmit? submit,
  }) =>
      ContentComplaintButton(
        key: key ?? const ValueKey('content_report_realty'),
        targetType: 'realty_listing',
        targetId: listing.id,
        isMine: () => realtyIsMine(listing, ownerKeyLoader),
        submit: submit,
      );

  final String targetType;
  final String targetId;
  final String restaurantId;
  final Future<bool> Function() isMine;
  final bool closeSheetFirst;
  final ContentComplaintSubmit? submit;

  /// Жорий фойдаланувчи (Firebase йўқ/логинсиз — бўш).
  static String currentPhone() {
    try {
      return canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
    } catch (_) {
      return '';
    }
  }

  /// Аъзолик натижаси сессия давомида (ресторан → ҳа/йўқ): ҳар варақда қайта ўқилмасин (37-банд).
  static final Map<String, bool> _memberCache = {};

  @visibleForTesting
  static void clearMemberCache() => _memberCache.clear();

  /// Эга (`ownerUid`) ёки аъзо (`restaurants/{id}/members/{мен}` — фақат аъзо ўқий олади, бегонага рад).
  /// [me], [memberLookup] — тест учун (ҳақиқийси: Firebase телефони ва `members/{мен}` ҳужжати).
  static Future<bool> restaurantIsMine(
    Restaurant r, {
    String? me,
    Future<bool> Function(String restaurantId, String phone)? memberLookup,
  }) async {
    final phone = me ?? currentPhone();
    if (phone.isEmpty) return false;
    if (r.ownerUid.isNotEmpty && phonesMatch(r.ownerUid, phone)) return true;
    final cacheKey = '${r.id}|$phone';
    final cached = _memberCache[cacheKey];
    if (cached != null) return cached;
    bool member;
    try {
      member = await (memberLookup ?? _memberDocExists)(r.id, phone);
    } on FirebaseException catch (e) {
      // Бегона — қоида ўқишни рад этади: демак аъзо эмас (кешланади). Тармоқ хатоси — кешланмайди.
      if (e.code != 'permission-denied') return false;
      member = false;
    } catch (_) {
      return false;
    }
    _memberCache[cacheKey] = member;
    return member;
  }

  static Future<bool> _memberDocExists(String restaurantId, String phone) async {
    final snap = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(restaurantId)
        .collection('members')
        .doc(phone)
        .get();
    return snap.exists;
  }

  /// Эгаси ёки жамоа аъзоси (бир хил `realtyOwnerKey`).
  static Future<bool> realtyIsMine(RealtyListing l, Future<String> Function()? ownerKeyLoader) async {
    if (l.ownerKey.isEmpty) return false;
    try {
      final key = await (ownerKeyLoader ?? RealtyRepository().myOwnerKey)();
      return key.isNotEmpty && key == l.ownerKey;
    } catch (_) {
      return false;
    }
  }

  @override
  State<ContentComplaintButton> createState() => _ContentComplaintButtonState();
}

class _ContentComplaintButtonState extends State<ContentComplaintButton> {
  /// null — ҳали аниқланмаган (тугма кўринмайди).
  bool? _mine;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    var mine = false;
    try {
      mine = await widget.isMine();
    } catch (_) {
      mine = false;
    }
    if (mounted) setState(() => _mine = mine);
  }

  Future<void> _open() async {
    var host = context;
    if (widget.closeSheetFirst) {
      final nav = Navigator.of(context);
      host = nav.context;
      nav.pop();
    }
    final w = widget;
    final submit = w.submit ?? ContentComplaintRepository().submit;
    await showComplaintSheet(
      host,
      reasons: contentComplaintReasons,
      keyPrefix: 'content_report',
      ownKey: 'content_report_own',
      send: (reason, comment) => submit(
        targetType: w.targetType,
        targetId: w.targetId,
        restaurantId: w.restaurantId,
        reason: reason,
        comment: comment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mine != false) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const ValueKey('content_report_entry'),
        style: TextButton.styleFrom(foregroundColor: muted, minimumSize: const Size(48, 48)),
        onPressed: _open,
        icon: const Icon(Icons.flag_outlined, size: 18),
        label: Text(context.tr('content_report_entry')),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/admin_auth_service.dart';
import '../services/admin_market_service.dart';

/// Харидор шикояти (`reports`): дўкон/маҳсулот (`type: shop_content`, `submitShopComplaint`) ҳамда
/// ресторан/таом (`restaurant_content`) ва кўчмас мулк эълони (`realty_content`, `submitContentComplaint`).
/// Битта модел ва битта панел — ҳар модул ўз бўлимида ўз [FirestoreShopComplaintsSource.type] билан кўрсатади.
class ShopComplaint {
  const ShopComplaint({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.ownerPhone,
    required this.title,
    required this.reason,
    required this.reporterId,
    this.restaurantId = '',
    this.comment = '',
    this.createdAt,
  });

  final String id;

  /// `shop_item` | `shop` | `restaurant` | `restaurant_item` | `realty_listing`
  final String targetType;
  final String targetId;

  /// Фақат дўкон шикоятида (ресторан/кўчмас мулкда эга телефони ёзилмайди).
  final String ownerPhone;
  final String title;

  /// Дўкон: ўзбекча матн; ресторан/кўчмас мулк: код (`fraud`, `wrong_info`, `spam`, `abuse`, `other`).
  final String reason;
  final String reporterId;

  /// `restaurant_item` учун таомнинг ресторани.
  final String restaurantId;

  /// Ихтиёрий изоҳ (`other` да мажбурий).
  final String comment;
  final DateTime? createdAt;

  static String _s(Object? v) => v is String ? v : '';

  factory ShopComplaint.fromMap(String id, Map<String, dynamic> d) => ShopComplaint(
        id: id,
        targetType: _s(d['targetType']),
        targetId: _s(d['targetId']),
        ownerPhone: _s(d['ownerPhone']),
        title: _s(d['title']),
        reason: _s(d['reason']),
        reporterId: _s(d['reporterId']),
        restaurantId: _s(d['restaurantId']),
        comment: _s(d['comment']),
        createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
      );

  /// Сабаб коди → админ матни (сервердаги `REASONS`); дўконнинг эркин матни ўзгармайди.
  static const reasonLabels = <String, String>{
    'fraud': 'Алдов ёки фирибгарлик',
    'wrong_info': 'Нотўғри маълумот',
    'spam': 'Спам / Такрорий',
    'abuse': 'Ҳақоратли матн',
    'other': 'Бошқа сабаб',
  };

  String get reasonLabel => reasonLabels[reason] ?? reason;

  String get targetLabel {
    final name = title.isEmpty ? targetId : title;
    return switch (targetType) {
      'shop' => 'Дўкон',
      'restaurant' => 'Ресторан: $name',
      'restaurant_item' => 'Таом: $name',
      'realty_listing' => 'Эълон: $name',
      _ => 'Маҳсулот: $name',
    };
  }
}

/// Шикоятлар манбаи: Firestore (админ ўқийди, rules: `reports` — фақат админ) ва ёпиш — мавжуд умумий
/// `adminResolveDatingReport` callable (ҳар қандай `reports` ҳужжатини `resolved` қилади, ким/қачон билан).
abstract class ShopComplaintsSource {
  Stream<List<ShopComplaint>> watchOpen();
  Future<void> resolve(BuildContext context, String reportId);
}

class FirestoreShopComplaintsSource implements ShopComplaintsSource {
  const FirestoreShopComplaintsSource({this.type = 'shop_content'});

  /// `reports.type`: `shop_content` | `restaurant_content` | `realty_content`.
  final String type;

  @override
  Stream<List<ShopComplaint>> watchOpen() => FirebaseFirestore.instance
      .collection('reports')
      .where('type', isEqualTo: type)
      .where('status', isEqualTo: 'open')
      .limit(200)
      .snapshots()
      .map((s) {
        final list = [for (final d in s.docs) ShopComplaint.fromMap(d.id, d.data())];
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        list.sort((a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
        return list;
      });

  @override
  Future<void> resolve(BuildContext context, String reportId) {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    return context.read<AdminMarketService>().resolveComplaint(adminPhone: adminPhone, reportId: reportId);
  }
}

/// Шикоятга модул амали (масалан кўчмас мулкда «Блоклаш»): бажарилгач шикоят ҳам ёпилади.
typedef ComplaintAction = ({String label, Future<void> Function(BuildContext context, ShopComplaint c) run});

/// Очиқ шикоятлар рўйхати: [onOpenOwner] берилса «Дўконни очиш» (дўкон бўлими), [action] берилса модул амали,
/// «Ҳал қилинди» — шикоят ёпилади.
class ShopComplaintsPanel extends StatefulWidget {
  const ShopComplaintsPanel({super.key, required this.source, this.onOpenOwner, this.action, this.maxListHeight});

  final ShopComplaintsSource source;
  final ValueChanged<String>? onOpenOwner;
  final ComplaintAction? action;

  /// `Column` + `Expanded` ичида (скролсиз экран): рўйхат шу баландликдан ошса ичида айланади.
  final double? maxListHeight;

  @override
  State<ShopComplaintsPanel> createState() => _ShopComplaintsPanelState();
}

class _ShopComplaintsPanelState extends State<ShopComplaintsPanel> {
  static final _date = DateFormat('dd.MM HH:mm');
  late final Stream<List<ShopComplaint>> _stream = widget.source.watchOpen();
  String? _busyId;

  Future<void> _run(ShopComplaint c, Future<void> Function() body) async {
    setState(() => _busyId = c.id);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await body();
    } catch (e) {
      debugPrint('[ShopComplaints] ${c.id}: $e');
      messenger?.showSnackBar(const SnackBar(content: Text('Бажариб бўлмади. Қайта уриниб кўринг.')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _resolve(ShopComplaint c) => _run(c, () => widget.source.resolve(context, c.id));

  /// Охирги кўрсатилган очиқ шикоятлар — амалдан кейин ШУ объектга келган бошқа шикоятлар ҳам ёпилади.
  List<ShopComplaint> _latest = const [];

  Future<void> _act(ShopComplaint c, ComplaintAction a) => _run(c, () async {
        await a.run(context, c);
        if (!mounted) return;
        // Амал объектга тегишли (масалан эълон блокланди): унга келган БАРЧА очиқ шикоятлар ёпилади,
        // фақат босилгани эмас — бошқалари рўйхатда «очиқ» бўлиб қолмасин.
        final sameTarget = [
          c,
          for (final o in _latest)
            if (o.id != c.id && o.targetType == c.targetType && o.targetId == c.targetId) o,
        ];
        try {
          for (final o in sameTarget) {
            if (!mounted) return;
            await widget.source.resolve(context, o.id);
          }
        } catch (e) {
          // Амал БАЖАРИЛДИ (масалан эълон блокланди) — фақат шикоят ёпилмади: админ буни аниқ билсин.
          debugPrint('[ShopComplaints] ${c.id} resolve after action: $e');
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              content: Text('«${a.label}» бажарилди, лекин шикоят ёпилмади. «Ҳал қилинди»ни қайта босинг.'),
            ));
          }
        }
      });

  IconData _icon(String t) => switch (t) {
        'shop' => Icons.storefront_rounded,
        'restaurant' => Icons.restaurant_rounded,
        'restaurant_item' => Icons.lunch_dining_outlined,
        'realty_listing' => Icons.home_work_outlined,
        _ => Icons.inventory_2_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final onOpenOwner = widget.onOpenOwner;
    final action = widget.action;
    return StreamBuilder<List<ShopComplaint>>(
      stream: _stream,
      builder: (context, snap) {
        final list = snap.data ?? const <ShopComplaint>[];
        _latest = list;
        if (snap.hasError || list.isEmpty) return const SizedBox.shrink();
        final tiles = [for (final c in list) _tile(c, onOpenOwner, action)];
        final maxH = widget.maxListHeight;
        return Card(
          key: const ValueKey('shop_complaints_panel'),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          color: Colors.red.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Очиқ шикоятлар: ${list.length}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade800)),
              ),
              if (maxH == null)
                ...tiles
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: ListView(shrinkWrap: true, children: tiles),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(ShopComplaint c, ValueChanged<String>? onOpenOwner, ComplaintAction? action) => ListTile(
        key: ValueKey('shop_complaint_${c.id}'),
        dense: true,
        leading: Icon(_icon(c.targetType)),
        title: Text(c.comment.isEmpty ? c.reasonLabel : '${c.reasonLabel}: ${c.comment}'),
        subtitle: Text([
          c.targetLabel,
          if (c.ownerPhone.isNotEmpty) 'эга: ${c.ownerPhone}',
          'шикоятчи: ${c.reporterId}',
          if (c.createdAt != null) _date.format(c.createdAt!),
        ].join(' · ')),
        trailing: _busyId == c.id
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Wrap(spacing: 4, children: [
                if (onOpenOwner != null)
                  TextButton(
                    onPressed: c.ownerPhone.isEmpty ? null : () => onOpenOwner(c.ownerPhone),
                    child: const Text('Дўконни очиш'),
                  ),
                if (action != null)
                  TextButton(
                    key: ValueKey('shop_complaint_action_${c.id}'),
                    onPressed: () => _act(c, action),
                    child: Text(action.label),
                  ),
                TextButton(
                  key: ValueKey('shop_complaint_resolve_${c.id}'),
                  onPressed: () => _resolve(c),
                  child: const Text('Ҳал қилинди'),
                ),
              ]),
      );
}

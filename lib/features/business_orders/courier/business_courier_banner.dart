// Курьер панелидаги «Дўкон буюртмалари» баннери (ресторан баннери ёнида). Кўриниш — сервер дарвозаси
// (`getBusinessOrdersAccess`, [BusinessOrdersAccess.courierVisible]): модул ёпиқ ёки фақат синовчиларга бўлса
// (курьер синовчи бўлмаса) — баннер йўқ (ўлик кириш йўқ). Хато — ёпиқ.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import 'business_nearby_orders_screen.dart';

class BusinessCourierBanner extends StatefulWidget {
  const BusinessCourierBanner({super.key, required this.onClaimed, this.repository, this.accessCheck});

  /// Курьер буюртма олди — маршрутни қайта юклаш.
  final VoidCallback onClaimed;
  final BusinessOrdersRepository? repository;

  /// Тест учун: дарвоза жавоби.
  final Future<BusinessOrdersAccess> Function()? accessCheck;

  @override
  State<BusinessCourierBanner> createState() => _BusinessCourierBannerState();
}

class _BusinessCourierBannerState extends State<BusinessCourierBanner> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    try {
      final a = await (widget.accessCheck?.call() ?? _repo.access());
      if (mounted && a.courierVisible != _visible) setState(() => _visible = a.courierVisible);
    } catch (e) {
      debugPrint('[BizCourierBanner] $e');
    }
  }

  Future<void> _open() async {
    final claimed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BusinessNearbyOrdersScreen(repository: _repo)),
    );
    if (claimed == true) widget.onClaimed();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final c = context.ava;
    return Material(
      key: const ValueKey('biz_courier_banner'),
      color: c.brandSoft,
      child: InkWell(
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            ExcludeSemantics(child: Icon(Icons.storefront_rounded, size: 22, color: c.brandText)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('biz_order_courier_banner'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.brandText),
              ),
            ),
            Icon(Icons.chevron_right, color: c.brandText),
          ]),
        ),
      ),
    );
  }
}

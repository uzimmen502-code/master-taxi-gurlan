import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../business_map/data/business_repository.dart';

/// Дўконнинг доимий ҳаволаси ва QR-коди (эга қарори 2026-10-25, 5-босқич). Ҳавола бир марта берилади ва ўзгармайди
/// (дўкон номи ўзгарса ҳам ишлайди), телефон рақами йўқ. QR — визитка, пештахта, қадоқ ва ташқи реклама учун:
/// улашилади ёки скриншот қилиб чоп этилади. Манба белгиси: QR → `?src=qr`, улашилган ҳавола → `?src=link`
/// (6-босқич статистикаси учун).
/// Ҳаволага манба белгиси: `qr` (QR-коддан) ёки `link` (улашилган ҳавола).
String shopLinkWithSource(String url, String src) => '$url?src=$src';

Future<void> showShopLinkSheet(
  BuildContext context, {
  required String title,
  String businessId = '',
  Future<String> Function({String businessId})? loadLink,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ShopLinkSheet(title: title, businessId: businessId, loadLink: loadLink),
  );
}

class ShopLinkSheet extends StatefulWidget {
  const ShopLinkSheet({super.key, required this.title, this.businessId = '', this.loadLink});

  final String title;
  final String businessId;

  /// Тест учун алмаштирилади; бўлмаса `getMyShopLink` callable.
  final Future<String> Function({String businessId})? loadLink;

  @override
  State<ShopLinkSheet> createState() => _ShopLinkSheetState();
}

class _ShopLinkSheetState extends State<ShopLinkSheet> {
  final _qrKey = GlobalKey();
  late final Future<String> _url = _load();

  Future<String> _load() {
    final load = widget.loadLink ?? BusinessRepository().getMyShopLink;
    return load(businessId: widget.businessId);
  }

  static String withSource(String url, String src) => shopLinkWithSource(url, src);

  void _snack(String key) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr(key))));

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: withSource(url, 'link')));
    if (mounted) _snack('shop_link_copied');
  }

  Future<void> _shareLink(String url) => Share.share('${widget.title}\n${withSource(url, 'link')}');

  /// QR расмини PNG қилиб улашиш (веб ва телефонда бир хил — `XFile.fromData`).
  Future<void> _shareQr() async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      await Share.shareXFiles(
        [XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png', name: 'ava_dokon_qr.png')],
        text: widget.title,
      );
    } catch (e) {
      debugPrint('[ShopLink] qr share: $e');
      if (mounted) _snack('shop_link_err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: FutureBuilder<String>(
        future: _url,
        builder: (context, snap) {
          if (snap.hasError) {
            final code = BusinessRepository.errorCode(snap.error!);
            final blocked = code == 'SHOP_BLOCKED' || code == 'BUSINESS_BLOCKED';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                context.tr(blocked ? 'bizprod_blocked_banner' : 'shop_link_err'),
                key: const ValueKey('shop_link_error'),
                textAlign: TextAlign.center,
              ),
            );
          }
          if (!snap.hasData) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
          }
          final url = snap.data!;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.tr('shop_link_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(widget.title, style: TextStyle(color: Colors.grey.shade700), textAlign: TextAlign.center),
                const SizedBox(height: 14),
                RepaintBoundary(
                  key: _qrKey,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        QrImageView(
                          key: const ValueKey('shop_link_qr'),
                          data: withSource(url, 'qr'),
                          version: QrVersions.auto,
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 4),
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(url, key: const ValueKey('shop_link_url'), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(context.tr('shop_link_hint'),
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('shop_link_copy'),
                      onPressed: () => _copy(url),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(context.tr('shop_link_copy')),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('shop_link_share'),
                      onPressed: () => _shareLink(url),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: Text(context.tr('shop_link_share')),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('shop_link_share_qr'),
                      onPressed: _shareQr,
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: Text(context.tr('shop_link_share_qr')),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

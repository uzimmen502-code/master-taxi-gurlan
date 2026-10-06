// AVA Logistics — QR ва кодлар варағи (D-5, D-6).
//
// Эгаси: QR + топшириш коди + ҚАБУЛ ҚИЛИШ коди (охиргисини фақат қабул
// қилувчига айтади). Жорий custodian ижрочи: QR + топшириш коди (кейинги
// ижрочига кўрсатиш учун) — қабул қилиш коди СЕРВЕРДАН келмайди.
//
// Камера сканери — L13 (кейин муҳокама): ижрочи кодни ҚЎЛДА киритади,
// QR келгуси версия учун ҳозирдан кўрсатилади.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../domain/logistics_models.dart';

Future<void> showShipmentCodesSheet(BuildContext context, ShipmentSecrets s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.ava.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => ShipmentCodesSheet(secrets: s),
  );
}

class ShipmentCodesSheet extends StatelessWidget {
  const ShipmentCodesSheet({super.key, required this.secrets});

  final ShipmentSecrets secrets;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('logistics_codes'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${context.tr('logistics_tracking')}: ${secrets.trackingNumber}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.ink2),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line),
              ),
              child: QrImageView(
                data: secrets.qrPayload,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('logistics_qr_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.ink3),
          ),
          const SizedBox(height: 16),
          _CodeBlock(
            labelKey: 'logistics_handover_code',
            hintKey: 'logistics_handover_code_hint',
            code: secrets.handoverCode,
            color: c.brand,
            soft: c.brandSoft,
          ),
          if (secrets.deliveryCode != null) ...[
            const SizedBox(height: 12),
            _CodeBlock(
              labelKey: 'logistics_delivery_code',
              hintKey: 'logistics_delivery_code_hint',
              code: secrets.deliveryCode!,
              color: c.ok,
              soft: c.okSoft,
            ),
          ],
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.labelKey,
    required this.hintKey,
    required this.code,
    required this.color,
    required this.soft,
  });

  final String labelKey;
  final String hintKey;
  final String code;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    // «123 456» — ўқиш осон бўлсин.
    final pretty = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            context.tr(labelKey),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(height: 6),
          SelectableText(
            pretty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(hintKey),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.ink2),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../data/china_inquiry_repository.dart';
import '../screens/china_inquiries_screen.dart';
import '../screens/china_inquiry_form_screen.dart';

/// Хитой бозори экранидаги «Сўров қолдириш» блоки. Босқич ёпиқ (OFF / тестер эмас) бўлса
/// ҳеч нарса кўрсатилмайди — сервер `getChinaInquiryAccess` ҳал қилади.
class ChinaInquiryEntry extends StatefulWidget {
  const ChinaInquiryEntry({super.key, required this.phone, ChinaInquiryRepository? repository})
      : _repo = repository;

  final String phone;
  final ChinaInquiryRepository? _repo;

  @override
  State<ChinaInquiryEntry> createState() => _ChinaInquiryEntryState();
}

class _ChinaInquiryEntryState extends State<ChinaInquiryEntry> {
  // Бир марта сўралади: экран қайта чизилса сервер қайта чақирилмасин (37-банд).
  late final Future<bool> _access = (widget._repo ?? ChinaInquiryRepository()).hasAccess();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _access,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('china_inq_banner_title'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(context.tr('china_inq_banner_body')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChinaInquiryFormScreen()),
                        ),
                        child: Text(context.tr('china_inq_banner_cta')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ChinaInquiriesScreen(phone: widget.phone)),
                        ),
                        child: Text(context.tr('china_inq_my')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

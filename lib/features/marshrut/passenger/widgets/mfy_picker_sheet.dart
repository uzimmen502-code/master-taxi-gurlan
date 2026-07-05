import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../utils/gurlan_places.dart';

/// MFY tanlash uchun bottom sheet (Phase B).
Future<String?> showMarshrutMfyPickerSheet(
  BuildContext context, {
  required String title,
  required List<String> recentPlaces,
  String initialQuery = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MarshrutMfyPickerSheet(
      title: title,
      recentPlaces: recentPlaces,
      initialQuery: initialQuery,
    ),
  );
}

class _MarshrutMfyPickerSheet extends StatefulWidget {
  const _MarshrutMfyPickerSheet({
    required this.title,
    required this.recentPlaces,
    required this.initialQuery,
  });

  final String title;
  final List<String> recentPlaces;
  final String initialQuery;

  @override
  State<_MarshrutMfyPickerSheet> createState() => _MarshrutMfyPickerSheetState();
}

class _MarshrutMfyPickerSheetState extends State<_MarshrutMfyPickerSheet> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> _suggestions() {
    final q = _ctrl.text.trim();
    final recent = widget.recentPlaces
        .where(
          (p) => q.isEmpty || p.toLowerCase().contains(q.toLowerCase()),
        )
        .toList();
    if (q.length >= 2) {
      final places = GurlanPlaces.search(_ctrl.text);
      final seen = <String>{};
      final merged = <String>[];
      for (final p in recent) {
        if (seen.add(p)) merged.add(p);
      }
      for (final p in places) {
        if (seen.add(p)) merged.add(p);
      }
      return merged;
    }
    return recent;
  }

  void _pick(String value) => Navigator.pop(context, value);

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions();
    final recentSet = widget.recentPlaces.toSet();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: AppText.titleMedium,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.tr('marshrut_mfy_search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: suggestions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.tr('marshrut_mfy_no_results'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      itemCount: suggestions.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.grey.shade200,
                      ),
                      itemBuilder: (_, i) {
                        final place = suggestions[i];
                        final isRecent = recentSet.contains(place);
                        return ListTile(
                          leading: Icon(
                            isRecent ? Icons.history : Icons.location_on,
                            color: isRecent
                                ? Colors.grey.shade600
                                : AppColors.primary,
                          ),
                          title: Text(place),
                          onTap: () => _pick(place),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

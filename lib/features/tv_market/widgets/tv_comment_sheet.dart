import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/tv_clip.dart';
import '../models/tv_comment.dart';
import '../repositories/tv_clips_repository.dart';
import 'tv_owner_avatar.dart';

/// Изоҳлар шифти — фақат тайёр саволлар (эркин матн йўқ, spam хавфи паст).
/// Чақирувчи томон auth текширувини аллақачон ўтказган бўлиши керак.
Future<void> openTvCommentSheet(
  BuildContext context, {
  required TvClip clip,
  required String viewerPhone,
  required String viewerDisplayName,
  required VoidCallback onCommentAdded,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _TvCommentSheet(
      clip: clip,
      viewerPhone: viewerPhone,
      viewerDisplayName: viewerDisplayName,
      onCommentAdded: onCommentAdded,
    ),
  );
}

class _TvCommentSheet extends StatefulWidget {
  const _TvCommentSheet({
    required this.clip,
    required this.viewerPhone,
    required this.viewerDisplayName,
    required this.onCommentAdded,
  });

  final TvClip clip;
  final String viewerPhone;
  final String viewerDisplayName;
  final VoidCallback onCommentAdded;

  @override
  State<_TvCommentSheet> createState() => _TvCommentSheetState();
}

class _TvCommentSheetState extends State<_TvCommentSheet> {
  final _repo = TvClipsRepository();
  final _textCtrl = TextEditingController();
  List<TvComment> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.fetchComments(widget.clip.id);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendQuick(String key) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      await _repo.addQuickComment(
        clipId: widget.clip.id,
        authorPhone: widget.viewerPhone,
        authorName: widget.viewerDisplayName,
        key: key,
      );
      if (!mounted) return;
      widget.onCommentAdded();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (_sending || text.isEmpty || text.length > tvCommentTextMaxLen) return;
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      await _repo.addTextComment(
        clipId: widget.clip.id,
        authorPhone: widget.viewerPhone,
        authorName: widget.viewerDisplayName,
        text: text,
      );
      if (!mounted) return;
      _textCtrl.clear();
      widget.onCommentAdded();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('tv_comment_title'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                context.tr('tv_comment_empty'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            itemCount: _comments.length,
                            itemBuilder: (context, i) {
                              final c = _comments[i];
                              final name = c.authorName.trim().isEmpty
                                  ? context.tr('tv_comment_title')
                                  : c.authorName.trim();
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TvOwnerAvatar(name: name, radius: 15),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            c.isFreeText
                                                ? c.text
                                                : context.tr('tv_comment_quick_${c.key}'),
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final key in tvCommentQuickKeys)
                      _QuickChip(
                        label: context.tr('tv_comment_quick_$key'),
                        enabled: !_sending,
                        onTap: () => _sendQuick(key),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        enabled: !_sending,
                        maxLength: tvCommentTextMaxLen,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: context.tr('tv_comment_write_hint'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          counterText:
                              '${_textCtrl.text.length}/$tvCommentTextMaxLen',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending || _textCtrl.text.trim().isEmpty
                          ? null
                          : _sendText,
                      icon: const Icon(Icons.send_rounded),
                      color: const Color(0xFF00A853),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF00E676).withValues(alpha: 0.14),
      side: BorderSide.none,
      onPressed: enabled ? onTap : null,
    );
  }
}

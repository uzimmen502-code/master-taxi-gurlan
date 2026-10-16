import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../services/tv_clip_link.dart';

/// Яратиш формасидаги ихтиёрий «Видеоролик қўшиш» қатори (`TvClipLink`).
class VideoOptionTile extends StatelessWidget {
  const VideoOptionTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.dense = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v == true),
      dense: dense,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(context.tr('link_video_optional')),
      subtitle: Text(context.tr('link_video_optional_hint')),
    );
  }
}

/// Эълон тафсилотида: боғланган видео бор бўлсагина «Видеони кўриш» тугмаси.
/// Битта эълон — битта сўров (тафсилот экрани, рўйхат эмас).
class LinkedVideoButton extends StatefulWidget {
  const LinkedVideoButton({
    super.key,
    required this.linkId,
    required this.ownerPhone,
    this.loader,
  });

  final String linkId;
  final String ownerPhone;

  /// Тест учун алмаштириладиган юклагич.
  final Future<TvClip?> Function()? loader;

  @override
  State<LinkedVideoButton> createState() => _LinkedVideoButtonState();
}

class _LinkedVideoButtonState extends State<LinkedVideoButton> {
  late Future<TvClip?> _future = _load();

  // Сўров фақат bir марта (ва `linkId` ўзгарса): ота виджет қайта қурилганда
  // (масалан, сават ўзгарганда) қайта сўралмайди — 36-қоида.
  Future<TvClip?> _load() => widget.loader != null
      ? widget.loader!()
      : TvClipsRepository()
          .fetchLinked(linkId: widget.linkId, ownerPhone: widget.ownerPhone)
          .catchError((Object _) => null);

  @override
  void didUpdateWidget(LinkedVideoButton old) {
    super.didUpdateWidget(old);
    if (old.linkId != widget.linkId || old.ownerPhone != widget.ownerPhone) {
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TvClip?>(
      future: _future,
      builder: (context, snap) {
        final clip = snap.data;
        if (clip == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: () => TvClipLink.open(context, clip),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: Text(context.tr('link_video_open')),
          ),
        );
      },
    );
  }
}

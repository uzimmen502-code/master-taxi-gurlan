import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';

/// T1 SPIKE — vaqtinchalik, faqat qo'lda ishga tushiriladigan sinov ekrani.
/// Hech qanday route/navigatsiyaga ulanmagan — ataylab. Sinash uchun
/// `lib/main.dart`dagi `home:`ni vaqtincha shu ekranga almashtiring,
/// sinab bo'lgach qaytaring. Ilovaning boshqa qismiga taʼsir qilmaydi.
///
/// Maqsad: `video_player` (video-core audit'da aniqlangan yagona player
/// qatlami) HLS multi-bitrate manifestni o'ynata oladimi va ExoPlayer
/// o'zi ABR (bitrate switch) qiladimi — shuni real qurilmada tekshirish.
/// Cloud Function: `hlsSpikeTranscode` (`functions/index.js`, T1 SPIKE
/// bloki) — faqat `hls_spike/{clipId}/` prefiksiga yozadi, prod
/// `videoVariants`/`tv_clip_variants/`ga tegmaydi.
class HlsSpikeTestScreen extends StatefulWidget {
  const HlsSpikeTestScreen({super.key});

  @override
  State<HlsSpikeTestScreen> createState() => _HlsSpikeTestScreenState();
}

// T1 SPIKE debug: `tools/t1_spike_local_test.js`dan `KEEP=1` bilan olingan
// manifest — auth muammosi bo'lsa ham qurilmada video_player/ABR sinovini
// alohida o'tkazish uchun. Doimiy emas — sinovdan keyin bo'sh qoldiring.
const _kDebugMasterUrl =
    'https://firebasestorage.googleapis.com/v0/b/master-taxi-gurlan.firebasestorage.app/o/hls_spike%2F04nKjdcnRiI1AwIc0dM9%2Fmaster.m3u8?alt=media&token=3c8b26ed-0d0b-4342-a4e9-3f5dbbd0cc58';

class _HlsSpikeTestScreenState extends State<HlsSpikeTestScreen> {
  final _repo = TvClipsRepository();
  final _functions = FirebaseFunctions.instance;
  final _urlController = TextEditingController(text: _kDebugMasterUrl);

  List<TvClip> _clips = [];
  TvClip? _selected;
  bool _loadingClips = true;
  bool _transcoding = false;
  bool _cleaning = false;
  String _log = '';
  String? _masterUrl;

  VideoPlayerController? _ctrl;
  VoidCallback? _sizeListener;
  final _sizeLog = <String>[];

  @override
  void initState() {
    super.initState();
    _loadClips();
  }

  Future<void> _loadClips() async {
    try {
      final clips = await _repo.fetchAllActive(limit: 5);
      if (!mounted) return;
      setState(() {
        _clips = clips;
        _selected = clips.isNotEmpty ? clips.first : null;
        _loadingClips = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _log = 'Kliplarni yuklashda xato: $e';
        _loadingClips = false;
      });
    }
  }

  Future<void> _transcode() async {
    final clip = _selected;
    if (clip == null) return;
    setState(() {
      _transcoding = true;
      _masterUrl = null;
      _log = 'hlsSpikeTranscode chaqirilmoqda (clipId=${clip.id})...';
    });
    try {
      final res = await _functions.httpsCallable(
        'hlsSpikeTranscode',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 8)),
      ).call({'clipId': clip.id, 'videoUrl': clip.videoUrl});
      final data = Map<String, dynamic>.from(res.data as Map);
      final masterUrl = data['masterUrl'] as String?;
      if (!mounted) return;
      setState(() {
        _masterUrl = masterUrl;
        _transcoding = false;
        _log = '$_log\nTayyor: $masterUrl';
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _transcoding = false;
        _log = '$_log\nXato (${e.code}): ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _transcoding = false;
        _log = '$_log\nXato: $e';
      });
    }
  }

  Future<void> _play() async {
    final url = _masterUrl;
    if (url == null) return;
    await _disposePlayer();
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _sizeLog.clear();
    _sizeListener = () {
      final size = ctrl.value.size;
      final label =
          '${DateTime.now().toIso8601String().substring(11, 19)}  '
          '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}  '
          'pos=${ctrl.value.position.inSeconds}s  '
          'buffered=${ctrl.value.buffered.isEmpty ? '-' : ctrl.value.buffered.last.end.inSeconds}s';
      if (_sizeLog.isEmpty || _sizeLog.last.split('  ').skip(1).first != label.split('  ').skip(1).first) {
        _sizeLog.add(label);
        if (mounted) setState(() {});
      }
    };
    ctrl.addListener(_sizeListener!);
    await ctrl.initialize();
    await ctrl.setLooping(false);
    await ctrl.play();
    if (!mounted) {
      ctrl.removeListener(_sizeListener!);
      await ctrl.dispose();
      return;
    }
    setState(() => _ctrl = ctrl);
  }

  Future<void> _disposePlayer() async {
    final ctrl = _ctrl;
    final listener = _sizeListener;
    if (ctrl != null && listener != null) ctrl.removeListener(listener);
    _sizeListener = null;
    _ctrl = null;
    if (ctrl != null) await ctrl.dispose();
  }

  Future<void> _cleanup() async {
    final clip = _selected;
    if (clip == null) return;
    setState(() => _cleaning = true);
    try {
      await _functions.httpsCallable('deleteHlsSpike').call({'clipId': clip.id});
      await _disposePlayer();
      if (!mounted) return;
      setState(() {
        _masterUrl = null;
        _cleaning = false;
        _log = '$_log\nhls_spike/${clip.id}/ tozalandi.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cleaning = false;
        _log = '$_log\nTozalashda xato: $e';
      });
    }
  }

  Future<void> _playFromField() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() => _masterUrl = url);
    await _play();
  }

  @override
  void dispose() {
    _urlController.dispose();
    unawaited(_disposePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('T1 SPIKE — HLS test')),
      body: _loadingClips
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_clips.isEmpty)
                      const Text('Aktiv TV clip topilmadi.')
                    else
                      DropdownButton<TvClip>(
                        value: _selected,
                        isExpanded: true,
                        items: _clips
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c.title.isEmpty ? c.id : c.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (c) => setState(() => _selected = c),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _selected == null || _transcoding ? null : _transcode,
                      child: Text(_transcoding ? 'Ishlanmoqda...' : 'HLS yasash'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _masterUrl == null ? null : _play,
                      child: const Text('Play (video_player)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _selected == null || _cleaning ? null : _cleanup,
                      child: Text(_cleaning ? 'Tozalanmoqda...' : 'hls_spike/ tozalash'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Yoki qo\'lda manifest URL (auth kerak emas):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextField(
                      controller: _urlController,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 11),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _playFromField,
                      child: const Text('Play from URL'),
                    ),
                    const SizedBox(height: 16),
                    if (_ctrl != null && _ctrl!.value.isInitialized)
                      AspectRatio(
                        aspectRatio: _ctrl!.value.aspectRatio,
                        child: VideoPlayer(_ctrl!),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Size/pozitsiya jurnali (ABR ishlasa — Size vaqti-vaqti '
                      'bilan o\'zgarishi kerak, tarmoqni sun\'iy sekinlashtirib '
                      'ko\'ring):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black87,
                      child: Text(
                        _sizeLog.isEmpty ? '(hali yo\'q)' : _sizeLog.join('\n'),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(_log, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
    );
  }
}

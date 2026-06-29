import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

import '../../../../models/entertainment_video.dart';
import '../../services/entertainment_cache_service.dart';
import '../../services/entertainment_storage.dart';

/// Offline/online video player (Android: ExoPlayer orqali).
class EntertainmentPlayerScreen extends StatefulWidget {
  const EntertainmentPlayerScreen({
    super.key,
    required this.video,
    this.primaryColor = AppColors.primary,
  });

  final EntertainmentVideo video;
  final Color primaryColor;

  @override
  State<EntertainmentPlayerScreen> createState() =>
      _EntertainmentPlayerScreenState();
}

class _EntertainmentPlayerScreenState extends State<EntertainmentPlayerScreen> {
  final _cache = EntertainmentCacheService();
  final _storage = EntertainmentStorage();
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      // 1. Lokal cache bo'lsa — darhol, offline o'ynatamiz.
      // 2. Aks holda — STREAM (faqat ko'rilayotgan qism buferlanadi),
      //    butun faylni yuklab o'tirmaymiz → trafik va xotira tejaladi.
      final VideoPlayerController vc;
      final cached = await _cache.localFile(widget.video.id);
      if (cached != null && cached.existsSync()) {
        vc = VideoPlayerController.file(cached);
      } else {
        var url = widget.video.downloadUrl;
        if (url.isEmpty) {
          url = await _storage.downloadUrl(widget.video.storagePath);
        }
        if (url.isEmpty) {
          throw Exception('Видео манзили топилмади.');
        }
        vc = VideoPlayerController.networkUrl(Uri.parse(url));
      }
      await vc.initialize();
      final chewie = ChewieController(
        videoPlayerController: vc,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: widget.primaryColor,
          handleColor: widget.primaryColor,
        ),
      );

      if (!mounted) return;
      setState(() {
        _videoController = vc;
        _chewieController = chewie;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.video.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'Тайёрланмоқда…',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                )
              : _chewieController != null
                  ? Center(child: Chewie(controller: _chewieController!))
                  : const SizedBox.shrink(),
    );
  }
}

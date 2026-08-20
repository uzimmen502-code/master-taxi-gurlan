import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// AVA расмий IG / Facebook / TikTok токенлари (CF `settings/tv_social`).
class TvSocialSettingsBar extends StatefulWidget {
  const TvSocialSettingsBar({super.key});

  @override
  State<TvSocialSettingsBar> createState() => _TvSocialSettingsBarState();
}

class _TvSocialSettingsBarState extends State<TvSocialSettingsBar> {
  bool _open = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _pageTokenSet = false;
  bool _tiktokTokenSet = false;
  final _pageId = TextEditingController();
  final _igId = TextEditingController();
  final _caption = TextEditingController();
  final _pageToken = TextEditingController();
  final _tiktokToken = TextEditingController();
  final _tiktokRefresh = TextEditingController();
  final _tiktokKey = TextEditingController();
  final _tiktokSecret = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageId.dispose();
    _igId.dispose();
    _caption.dispose();
    _pageToken.dispose();
    _tiktokToken.dispose();
    _tiktokRefresh.dispose();
    _tiktokKey.dispose();
    _tiktokSecret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('adminGetTvSocialSettings')
          .call();
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final s = Map<String, dynamic>.from(data['settings'] as Map? ?? {});
      if (!mounted) return;
      _pageId.text = '${s['facebookPageId'] ?? ''}';
      _igId.text = '${s['instagramUserId'] ?? ''}';
      _caption.text = '${s['captionPrefix'] ?? ''}';
      _pageTokenSet = s['pageTokenSet'] == true;
      _tiktokTokenSet = s['tiktokTokenSet'] == true;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'facebookPageId': _pageId.text.trim(),
        'instagramUserId': _igId.text.trim(),
        'captionPrefix': _caption.text.trim(),
        'tiktokClientKey': _tiktokKey.text.trim(),
      };
      if (_pageToken.text.trim().isNotEmpty) {
        payload['facebookPageAccessToken'] = _pageToken.text.trim();
      }
      if (_tiktokToken.text.trim().isNotEmpty) {
        payload['tiktokAccessToken'] = _tiktokToken.text.trim();
      }
      if (_tiktokRefresh.text.trim().isNotEmpty) {
        payload['tiktokRefreshToken'] = _tiktokRefresh.text.trim();
      }
      if (_tiktokSecret.text.trim().isNotEmpty) {
        payload['tiktokClientSecret'] = _tiktokSecret.text.trim();
      }
      await FirebaseFunctions.instance
          .httpsCallable('adminSetTvSocialSettings')
          .call(payload);
      _pageToken.clear();
      _tiktokToken.clear();
      _tiktokRefresh.clear();
      _tiktokSecret.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Соцсет созламалари сақланди')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _pageTokenSet &&
        _pageId.text.trim().isNotEmpty &&
        _igId.text.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(
              ready ? Icons.public : Icons.public_off,
              color: ready ? Colors.green.shade700 : Colors.blueGrey,
            ),
            title: const Text(
              'AVA расмий Instagram / Facebook / TikTok',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            subtitle: Text(
              _loading
                  ? 'Юкланмоқда…'
                  : (_error != null
                      ? _error!
                      : (ready
                          ? 'Тизим жойлайди — токен сақланган'
                          : 'Токен ва Page/IG ID киритинг')),
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                color: _error != null ? Colors.red : Colors.black54,
              ),
            ),
            trailing: Icon(_open ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _open = !_open),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _loading
                  ? const LinearProgressIndicator()
                  : Column(
                      children: [
                        _field(_pageId, 'Facebook Page ID'),
                        _field(_igId, 'Instagram User ID (professional)'),
                        _field(
                          _pageToken,
                          _pageTokenSet
                              ? 'Page Access Token (янги — бўш қолдиринг)'
                              : 'Page Access Token',
                          obscure: true,
                        ),
                        _field(_caption, 'Подпись префикси (ихтиёрий)'),
                        _field(
                          _tiktokToken,
                          _tiktokTokenSet
                              ? 'TikTok access token (янги — бўш қолдиринг)'
                              : 'TikTok access token',
                          obscure: true,
                        ),
                        _field(_tiktokRefresh, 'TikTok refresh token',
                            obscure: true),
                        _field(_tiktokKey, 'TikTok client key'),
                        _field(_tiktokSecret, 'TikTok client secret',
                            obscure: true),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined, size: 18),
                            label: const Text('Сақлаш'),
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

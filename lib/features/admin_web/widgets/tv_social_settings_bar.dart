import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/ava_tokens.dart';

/// AVA расмий IG / Facebook / YouTube / Telegram токенлари
/// (CF `settings/tv_social`).
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
  bool _ytRefreshSet = false;
  bool _ytSecretSet = false;
  bool _tgBotTokenSet = false;
  final _pageId = TextEditingController();
  final _igId = TextEditingController();
  final _caption = TextEditingController();
  final _pageToken = TextEditingController();
  final _ytClientId = TextEditingController();
  final _ytSecret = TextEditingController();
  final _ytRefresh = TextEditingController();
  final _tgChannelId = TextEditingController();
  final _tgBotToken = TextEditingController();

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
    _ytClientId.dispose();
    _ytSecret.dispose();
    _ytRefresh.dispose();
    _tgChannelId.dispose();
    _tgBotToken.dispose();
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
      _ytClientId.text = '${s['youtubeClientId'] ?? ''}';
      _ytRefreshSet = s['youtubeRefreshSet'] == true;
      _ytSecretSet = s['youtubeSecretSet'] == true;
      _tgChannelId.text = '${s['telegramChannelId'] ?? ''}';
      _tgBotTokenSet = s['telegramBotTokenSet'] == true;
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
        'youtubeClientId': _ytClientId.text.trim(),
        'telegramChannelId': _tgChannelId.text.trim(),
      };
      if (_pageToken.text.trim().isNotEmpty) {
        payload['facebookPageAccessToken'] = _pageToken.text.trim();
      }
      if (_ytSecret.text.trim().isNotEmpty) {
        payload['youtubeClientSecret'] = _ytSecret.text.trim();
      }
      if (_ytRefresh.text.trim().isNotEmpty) {
        payload['youtubeRefreshToken'] = _ytRefresh.text.trim();
      }
      if (_tgBotToken.text.trim().isNotEmpty) {
        payload['telegramBotToken'] = _tgBotToken.text.trim();
      }
      await FirebaseFunctions.instance
          .httpsCallable('adminSetTvSocialSettings')
          .call(payload);
      _pageToken.clear();
      _ytSecret.clear();
      _ytRefresh.clear();
      _tgBotToken.clear();
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
              color: ready ? AvaLight.ok : Colors.blueGrey,
            ),
            title: const Text(
              'AVA расмий Instagram / Facebook / YouTube / Telegram',
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
                        _field(
                          _caption,
                          'Подпись префикси — CTA (макс. 200 белги!)',
                        ),
                        _field(_ytClientId, 'YouTube OAuth client ID'),
                        _field(
                          _ytSecret,
                          _ytSecretSet
                              ? 'YouTube client secret (янги — бўш қолдиринг)'
                              : 'YouTube client secret',
                          obscure: true,
                        ),
                        _field(
                          _ytRefresh,
                          _ytRefreshSet
                              ? 'YouTube refresh token (янги — бўш қолдиринг)'
                              : 'YouTube refresh token',
                          obscure: true,
                        ),
                        _field(_tgChannelId,
                            'Telegram канал ID (масалан @ava_gurlan)'),
                        _field(
                          _tgBotToken,
                          _tgBotTokenSet
                              ? 'Telegram bot token (янги — бўш қолдиринг)'
                              : 'Telegram bot token (BotFather)',
                          obscure: true,
                        ),
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

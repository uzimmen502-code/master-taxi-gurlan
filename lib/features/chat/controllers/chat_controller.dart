import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/chat_message.dart';
import '../../../repositories/chat_repository.dart';

/// ChatScreen uchun holatni boshqaradi.
class ChatController extends ChangeNotifier {
  ChatController({
    required ChatRepository repo,
    required this.chatId,
    required this.isAdmin,
  }) : _repo = repo {
    _loadMe();
  }

  final ChatRepository _repo;
  final String chatId;
  final bool isAdmin;

  String _myPhone = '';
  String _myName = '';

  String get myPhone => _myPhone;
  String get myName => _myName;

  /// Xabarlar real-time oqimi.
  Stream<List<ChatMessage>> get messages => _repo.watchMessages(chatId);

  Future<void> _loadMe() async {
    final prefs = await SharedPreferences.getInstance();
    _myPhone = phoneDigits(prefs.getString('user_phone') ?? '');
    _myName = prefs.getString('user_name') ?? '';
    notifyListeners();
  }

  /// Xabar yuborish. Bo'sh matn — hech narsa qilmaydi.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _repo.sendMessage(
      chatId: chatId,
      text: trimmed,
      fromAdmin: isAdmin,
      fromPhone: _myPhone,
      fromName: _myName,
    );
  }
}

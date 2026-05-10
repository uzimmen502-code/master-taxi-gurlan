import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatScreen extends StatefulWidget {
  final String targetPhone;
  final bool isAdmin;

  const ChatScreen({
    super.key,
    required this.targetPhone,
    this.isAdmin = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _db = FirebaseFirestore.instance;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _myPhone = '';
  String _myName = '';

  String get _chatId => _digits(widget.targetPhone);

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _digits(String v) => v.replaceAll(RegExp(r'[^\d]'), '');

  Future<void> _loadMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _myPhone = _digits(prefs.getString('user_phone') ?? '');
      _myName = prefs.getString('user_name') ?? '';
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    final isFromAdmin = widget.isAdmin;
    final chatRef = _db.collection('support_chats').doc(_chatId);
    await chatRef.set({
      'userPhone': _chatId,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': text,
      'lastFromAdmin': isFromAdmin,
    }, SetOptions(merge: true));
    await chatRef.collection('messages').add({
      'text': text,
      'fromAdmin': isFromAdmin,
      'fromPhone': _myPhone,
      'fromName': _myName,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
    await Future.delayed(const Duration(milliseconds: 120));
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isAdmin ? '💬 Мижоз чати' : '💬 Админ билан чат';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('support_chats')
                  .doc(_chatId)
                  .collection('messages')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Ҳозирча хабарлар йўқ'),
                  );
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final fromAdmin = (m['fromAdmin'] ?? false) as bool;
                    final mine = widget.isAdmin ? fromAdmin : !fromAdmin;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFF2E7D32)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          (m['text'] ?? '') as String,
                          style: TextStyle(
                            color: mine ? Colors.white : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Хабар ёзинг...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

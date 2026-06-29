import 'package:flutter/material.dart';

import '../../../models/dating_match.dart';
import '../../../repositories/dating_repository.dart';
import 'dating_profile_form_screen.dart' show datingAccent;

/// Match chat — faqat o'zaro qiziqish bildirgan ikki taraf.
class DatingChatScreen extends StatefulWidget {
  const DatingChatScreen({
    super.key,
    required this.myUid,
    required this.match,
  });

  final String myUid;
  final DatingMatch match;

  @override
  State<DatingChatScreen> createState() => _DatingChatScreenState();
}

class _DatingChatScreenState extends State<DatingChatScreen> {
  final _repo = DatingRepository();
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await _repo.sendMessage(
        matchId: widget.match.id,
        senderId: widget.myUid,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Хатолик: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherName = widget.match.otherName(widget.myUid);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F6),
      appBar: AppBar(
        title: Text(otherName.isEmpty ? 'Чат' : otherName),
        backgroundColor: datingAccent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<DatingMessage>>(
              stream: _repo.watchMessages(widget.match.id),
              builder: (context, snap) {
                final msgs = snap.data ?? const <DatingMessage>[];
                if (msgs.isEmpty) {
                  return Center(
                    child: Text('Биринчи хабарни ёзинг 👋',
                        style: TextStyle(color: Colors.grey.shade600)),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[msgs.length - 1 - i];
                    final mine = m.senderId == widget.myUid;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.74),
                        decoration: BoxDecoration(
                          color: mine ? datingAccent : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          m.text,
                          style: TextStyle(
                              color: mine ? Colors.white : Colors.black87),
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
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Хабар...',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    style:
                        IconButton.styleFrom(backgroundColor: datingAccent),
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send, color: Colors.white),
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/circle.dart';
import '../../../models/circle_chat_message.dart';
import '../../../models/circle_event.dart';
import '../../../models/circle_member.dart';
import '../../../models/circle_photo.dart';
import '../../../models/circle_post.dart';
import '../../../repositories/circles_repository.dart';
import '../services/circle_album_storage.dart';

/// Davra ekrani: A'zolar + Lenta + Uchrashuvlar + Albom. Leave + shikoyat.
class CircleScreen extends StatefulWidget {
  const CircleScreen({super.key, required this.circleId, required this.phone});

  final String circleId;
  final String phone;

  static const _accent = Color(0xFF6A4C93);

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> {
  final _repo = CirclesRepository();
  final _album = CircleAlbumStorage();
  final _picker = ImagePicker();
  final _postCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  String _myName = '';
  bool _sending = false;
  bool _uploading = false;
  bool _chatSending = false;

  @override
  void initState() {
    super.initState();
    _loadMyName();
  }

  Future<void> _loadMyName() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.phone)
          .get();
      final name = (snap.data()?['name'] ?? '').toString();
      if (name.isNotEmpty && mounted) setState(() => _myName = name);
    } catch (_) {}
  }

  @override
  void dispose() {
    _postCtrl.dispose();
    _chatCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────── Actions ───────────────────────────

  Future<void> _leave(Circle c) async {
    final ok = await _confirm('Давradан чиқиш',
        '«${c.title}» даврасидан чиқасизми?', 'Чиқаман', danger: true);
    if (ok != true) return;
    await _repo.leaveCircle(circleId: widget.circleId, userId: widget.phone);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _report({
    required String targetType,
    required String targetId,
  }) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Шикоят'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Сабаби (масалан: танимайман / нотўғри маълумот)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекор')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Юбориш')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.report(
      circleId: widget.circleId,
      targetType: targetType,
      targetId: targetId,
      reporterId: widget.phone,
      reason: reasonCtrl.text.trim(),
    );
    if (mounted) _snack('Шикоят юборилди.');
  }

  Future<void> _sendPost() async {
    final text = _postCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repo.createPost(
        circleId: widget.circleId,
        post: CirclePost(
          id: '',
          authorId: widget.phone,
          authorName: _myName,
          text: text,
        ),
      );
      _postCtrl.clear();
    } catch (e) {
      _snack('Хатолик: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendChat() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _chatSending) return;
    setState(() => _chatSending = true);
    try {
      await _repo.sendChat(
        circleId: widget.circleId,
        senderId: widget.phone,
        senderName: _myName,
        text: text,
      );
      _chatCtrl.clear();
    } catch (e) {
      _snack('Хатолик: $e');
    } finally {
      if (mounted) setState(() => _chatSending = false);
    }
  }

  Future<void> _createEvent() async {
    final titleCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    DateTime? picked;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Учрашув қўшиш'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Сарлавҳа *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: placeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Жой', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(picked == null
                      ? 'Сана ва вақтни танланг'
                      : _fmtTime(picked)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 1)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (d == null) return;
                    if (!ctx.mounted) return;
                    final t = await showTimePicker(
                        context: ctx, initialTime: TimeOfDay.now());
                    setLocal(() {
                      picked = DateTime(
                          d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Бекор')),
            ElevatedButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Сақлаш'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    await _repo.createEvent(
      circleId: widget.circleId,
      event: CircleEvent(
        id: '',
        title: titleCtrl.text.trim(),
        place: placeCtrl.text.trim(),
        createdBy: widget.phone,
        createdByName: _myName,
        dateTime: picked,
        attendees: {widget.phone: 'yes'},
      ),
    );
  }

  Future<void> _addPhoto() async {
    if (_uploading) return;
    final XFile? file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final res =
          await _album.uploadImage(circleId: widget.circleId, image: file);
      await _repo.addPhoto(
        circleId: widget.circleId,
        photo: CirclePhoto(
          id: '',
          uploaderId: widget.phone,
          uploaderName: _myName,
          url: res.url,
          storagePath: res.path,
        ),
      );
    } catch (e) {
      _snack('Юклашда хатолик: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Circle?>(
      stream: _repo.watchCircle(widget.circleId),
      builder: (context, snap) {
        final circle = snap.data;
        final isOwner = circle?.ownerId == widget.phone;
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: CircleScreen._accent,
              foregroundColor: Colors.white,
              title: Text(circle?.title ?? 'Давра'),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'leave' && circle != null) _leave(circle);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'leave', child: Text('Давradан чиқиш')),
                  ],
                ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(text: 'Аъзолар'),
                  Tab(text: 'Лента'),
                  Tab(text: 'Учрашувлар'),
                  Tab(text: 'Альбом'),
                  Tab(text: 'Чат'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _membersTab(),
                _feedTab(isOwner),
                _eventsTab(isOwner),
                _albumTab(isOwner),
                _chatTab(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── A'zolar ──
  Widget _membersTab() {
    return StreamBuilder<List<CircleMember>>(
      stream: _repo.watchMembers(widget.circleId),
      builder: (context, snap) {
        final members = snap.data ?? const <CircleMember>[];
        for (final m in members) {
          if (m.userId == widget.phone &&
              m.fullName.isNotEmpty &&
              _myName.isEmpty) {
            _myName = m.fullName;
          }
        }
        if (snap.connectionState == ConnectionState.waiting &&
            members.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (members.isEmpty) {
          return const Center(child: Text('Ҳали аъзолар йўқ.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: members.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _memberTile(members[i]),
        );
      },
    );
  }

  Widget _memberTile(CircleMember m) {
    final isMe = m.userId == widget.phone;
    final subtitle = [
      if (m.classLabel.isNotEmpty) '${m.classLabel}-синф',
      if (m.currentCity.isNotEmpty) m.currentCity,
      if (m.currentJob.isNotEmpty) m.currentJob,
      if (m.phoneVisible && m.phone.isNotEmpty) '📞 ${m.phone}',
    ].join(' · ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: CircleScreen._accent.withValues(alpha: 0.15),
        child: Text(
          m.fullName.isNotEmpty
              ? m.fullName.characters.first.toUpperCase()
              : '?',
          style: const TextStyle(
              color: CircleScreen._accent, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(m.fullName.isEmpty ? 'Номсиз' : m.fullName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (m.isOwner) ...[
            const SizedBox(width: 6),
            const Icon(Icons.star, size: 14, color: Colors.amber),
          ],
        ],
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: isMe
          ? null
          : IconButton(
              icon: const Icon(Icons.flag_outlined, size: 20),
              tooltip: 'Шикоят',
              onPressed: () =>
                  _report(targetType: 'member', targetId: m.userId),
            ),
    );
  }

  // ── Lenta ──
  Widget _feedTab(bool isOwner) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<CirclePost>>(
            stream: _repo.watchPosts(widget.circleId),
            builder: (context, snap) {
              final posts = snap.data ?? const <CirclePost>[];
              if (snap.connectionState == ConnectionState.waiting &&
                  posts.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (posts.isEmpty) {
                return const Center(child: Text('Ҳали эълон йўқ.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: posts.length,
                itemBuilder: (_, i) => _postTile(posts[i], isOwner),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _postCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Эълон ёзинг...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style:
                      IconButton.styleFrom(backgroundColor: CircleScreen._accent),
                  onPressed: _sending ? null : _sendPost,
                  icon: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _postTile(CirclePost p, bool isOwner) {
    final canDelete = p.authorId == widget.phone || isOwner;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.authorName.isEmpty ? 'Аъзо' : p.authorName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(_fmtTime(p.createdAt),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (v) {
                    if (v == 'delete') {
                      _repo.deletePost(
                          circleId: widget.circleId, postId: p.id);
                    } else if (v == 'report') {
                      _report(targetType: 'post', targetId: p.id);
                    }
                  },
                  itemBuilder: (_) => [
                    if (canDelete)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Ўчириш')),
                    if (!canDelete)
                      const PopupMenuItem(
                          value: 'report', child: Text('Шикоят')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(p.text),
          ],
        ),
      ),
    );
  }

  // ── Uchrashuvlar ──
  Widget _eventsTab(bool isOwner) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _createEvent,
              icon: const Icon(Icons.add),
              label: const Text('Учрашув қўшиш'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<CircleEvent>>(
            stream: _repo.watchEvents(widget.circleId),
            builder: (context, snap) {
              final events = snap.data ?? const <CircleEvent>[];
              if (snap.connectionState == ConnectionState.waiting &&
                  events.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (events.isEmpty) {
                return const Center(child: Text('Ҳали учрашув йўқ.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: events.length,
                itemBuilder: (_, i) => _eventTile(events[i], isOwner),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _eventTile(CircleEvent e, bool isOwner) {
    final my = e.rsvpOf(widget.phone);
    final canDelete = e.createdBy == widget.phone || isOwner;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(e.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _repo.deleteEvent(
                        circleId: widget.circleId, eventId: e.id),
                  ),
              ],
            ),
            if (e.dateTime != null)
              Text('🗓 ${_fmtTime(e.dateTime)}',
                  style: TextStyle(color: Colors.grey.shade700)),
            if (e.place.isNotEmpty)
              Text('📍 ${e.place}',
                  style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                _rsvpChip(e, 'yes', 'Бораман', my),
                _rsvpChip(e, 'maybe', 'Балки', my),
                _rsvpChip(e, 'no', 'Йўқ', my),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 6),
                  child: Text('✅ ${e.yesCount}',
                      style: TextStyle(color: Colors.grey.shade600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rsvpChip(CircleEvent e, String value, String label, String? my) {
    final selected = my == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: CircleScreen._accent.withValues(alpha: 0.2),
      onSelected: (_) => _repo.setRsvp(
        circleId: widget.circleId,
        eventId: e.id,
        userId: widget.phone,
        status: value,
      ),
    );
  }

  // ── Albom ──
  Widget _albumTab(bool isOwner) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _addPhoto,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_a_photo_outlined),
              label: Text(_uploading ? 'Юкланмоқда...' : 'Расм қўшиш'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<CirclePhoto>>(
            stream: _repo.watchPhotos(widget.circleId),
            builder: (context, snap) {
              final photos = snap.data ?? const <CirclePhoto>[];
              if (snap.connectionState == ConnectionState.waiting &&
                  photos.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (photos.isEmpty) {
                return const Center(child: Text('Ҳали расм йўқ.'));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: photos.length,
                itemBuilder: (_, i) => _photoTile(photos[i], isOwner),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _photoTile(CirclePhoto photo, bool isOwner) {
    final canDelete = photo.uploaderId == widget.phone || isOwner;
    return GestureDetector(
      onTap: () => _openPhoto(photo, canDelete),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          photo.url,
          fit: BoxFit.cover,
          loadingBuilder: (c, child, p) => p == null
              ? child
              : Container(
                  color: Colors.grey.shade200,
                  child: const Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)))),
          errorBuilder: (c, e, s) => Container(
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey)),
        ),
      ),
    );
  }

  void _openPhoto(CirclePhoto photo, bool canDelete) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: InteractiveViewer(child: Image.network(photo.url))),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      photo.uploaderName.isEmpty ? '' : photo.uploaderName,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                  if (canDelete)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('Ўчириш',
                          style: TextStyle(color: Colors.red)),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _repo.deletePhoto(
                            circleId: widget.circleId, photoId: photo.id);
                        await _album.deleteByUrl(photo.url);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Guruh chat ──
  Widget _chatTab() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<CircleChatMessage>>(
            stream: _repo.watchChat(widget.circleId),
            builder: (context, snap) {
              final msgs = snap.data ?? const <CircleChatMessage>[];
              if (snap.connectionState == ConnectionState.waiting &&
                  msgs.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (msgs.isEmpty) {
                return const Center(child: Text('Ҳали хабар йўқ.'));
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: msgs.length,
                itemBuilder: (_, i) => _chatBubble(msgs[msgs.length - 1 - i]),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Хабар ёзинг...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style:
                      IconButton.styleFrom(backgroundColor: CircleScreen._accent),
                  onPressed: _chatSending ? null : _sendChat,
                  icon: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chatBubble(CircleChatMessage m) {
    final isMe = m.senderId == widget.phone;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.74),
        decoration: BoxDecoration(
          color: isMe
              ? CircleScreen._accent.withValues(alpha: 0.9)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && m.senderName.isNotEmpty)
              Text(m.senderName,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: CircleScreen._accent)),
            Text(m.text,
                style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
            Text(_fmtTime(m.createdAt),
                style: TextStyle(
                    fontSize: 9,
                    color: isMe ? Colors.white70 : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── Helpers ───────────────────────────

  Future<bool?> _confirm(String title, String body, String okLabel,
      {bool danger = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Йўқ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger
                ? ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white)
                : null,
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}

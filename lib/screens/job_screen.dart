import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_theme.dart';

class JobScreen extends StatefulWidget {
  const JobScreen({super.key});
  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen>
    with SingleTickerProviderStateMixin {

  static const _blue  = Color(0xFF5D4037);
  static const _green = Color(0xFF795548);

  late TabController _tabCtrl;
  final _db         = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();

  String _searchQuery = '';
  String _userName    = '';
  String _userPhone   = '';
  String _userAddr    = '';
  bool _isAdmin       = false; // Админ текшириш

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadUser();
    _checkAdmin();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName  = prefs.getString('user_name')    ?? '';
      _userPhone = prefs.getString('user_phone')   ?? '';
      _userAddr  = prefs.getString('user_address') ?? '';
    });
  }

  Future<void> _checkAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final adminPhone = prefs.getString('admin_phone') ?? '';
    if (_userPhone.isNotEmpty && _userPhone == adminPhone) {
      setState(() => _isAdmin = true);
    }
    // Ёки Firestore'дан текшириш:
    // final doc = await _db.collection('admins').doc(_userPhone).get();
    // if (doc.exists) setState(() => _isAdmin = true);
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 60)  return '${diff.inMinutes} дақ. олдин';
    if (diff.inHours   < 24)  return '${diff.inHours} соат олдин';
    return '${diff.inDays} кун олдин';
  }

  bool _isExpired(Timestamp? exp) {
    if (exp == null) return false;
    return exp.toDate().isBefore(DateTime.now());
  }

  // ── Эълон қўшиш ──
  void _showAddDialog(String type) {
    final textCtrl = TextEditingController();
    bool isUrgent = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),

                  Row(children: [
                    Text(type == 'service' ? '🛠️' : '🔨',
                        style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(type == 'work' ? 'Иш эълони' : 'Хизмат таклифи',
                          style: const TextStyle(
                              fontSize: AppText.titleMedium, fontWeight: FontWeight.bold)),
                      Text(
                        type == 'service' ? '📅 30 кун давомида кўринади' : '📅 3 кун давомида кўринади',
                        style: TextStyle(fontSize: AppText.labelSmall,
                            color: type == 'service' ? _green : Colors.orange,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ]),
                  const SizedBox(height: 16),

                  // Матн майдони
                  TextField(
                    controller: textCtrl,
                    maxLines: 4, maxLength: 300,
                    decoration: InputDecoration(
                      hintText: type == 'work'
                          ? 'Масалан: Шоли экишга 5-6 одам керак'
                          : 'Масалан: Электрикман, бригадам бор',
                      hintStyle: TextStyle(
                          color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                          BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                          const BorderSide(color: _blue, width: 1.5)),
                      filled: true, fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Профилдан
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _blue.withOpacity(0.2)),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📌 Профилдан автоматик:',
                              style: TextStyle(fontSize: AppText.labelSmall,
                                  fontWeight: FontWeight.w600, color: _blue)),
                          const SizedBox(height: 4),
                          Text('📞 $_userPhone',
                              style: const TextStyle(fontSize: AppText.bodySmall)),
                          if (_userAddr.isNotEmpty)
                            Text('📍 $_userAddr',
                                style: const TextStyle(fontSize: AppText.bodySmall)),
                        ]),
                  ),
                  const SizedBox(height: 10),

                  // Шошилинч — ФАҚАТ "Иш бор" учун
                  if (type == 'work') ...[
                    GestureDetector(
                      onTap: () => setS(() => isUrgent = !isUrgent),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isUrgent
                              ? Colors.red.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isUrgent
                                  ? Colors.red.shade300
                                  : Colors.grey.shade300),
                        ),
                        child: Row(children: [
                          Text(isUrgent ? '🚨' : '⏰',
                              style: const TextStyle(fontSize: AppText.titleLarge)),
                          const SizedBox(width: 10),
                          Column(crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Шошилинч',
                                    style: TextStyle(fontSize: AppText.bodyMedium,
                                        fontWeight: FontWeight.w600,
                                        color: isUrgent
                                            ? Colors.red
                                            : Colors.grey.shade600)),
                                Text('Рўйхат бошига чиқади',
                                    style: TextStyle(
                                        fontSize: AppText.labelTiny,
                                        color: Colors.grey.shade500)),
                              ]),
                          const Spacer(),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: isUrgent ? Colors.red : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isUrgent
                                  ? Colors.red : Colors.grey.shade400),
                            ),
                            child: isUrgent
                                ? const Icon(Icons.check,
                                color: Colors.white, size: 14)
                                : null,
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Тасдиқлаш
                  ElevatedButton.icon(
                    onPressed: () async {
                      final text = textCtrl.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: const Text('Матнни киритинг'),
                          backgroundColor: Colors.red,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ));
                        return;
                      }

                      // Кунлик чеклов — 5 та
                      final today      = DateTime.now();
                      final startOfDay = DateTime(today.year, today.month, today.day);
                      try {
                        final countSnap = await _db.collection('ads')
                            .where('authorPhone', isEqualTo: _userPhone)
                            .where('createdAt',
                            isGreaterThan: Timestamp.fromDate(startOfDay))
                            .get();
                        if (countSnap.docs.length >= 5) {
                          if (mounted) Navigator.pop(context);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('⚠️ Кунига максимум 5 та эълон!'),
                                backgroundColor: Colors.orange,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ));
                          return;
                        }
                      } catch (_) {}

                      final expiresAt = Timestamp.fromDate(
                          today.add(Duration(days: type == 'service' ? 30 : 3)));

                      try {
                        await _db.collection('ads').add({
                          'type':        type,
                          'text':        text,
                          'authorName':  _userName,
                          'authorPhone': _userPhone,
                          'address':     _userAddr,
                          'isUrgent':    type == 'work' ? isUrgent : false,
                          'status':      'active',
                          'expiresAt':   expiresAt,
                          'createdAt':   FieldValue.serverTimestamp(),
                          'editedAt':    null,
                        });
                        if (mounted) Navigator.pop(context);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('✅ Эълон қўшилди!'),
                              backgroundColor: _green,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ));
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Хатолик: $e'),
                                backgroundColor: Colors.red));
                      }
                    },
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('ЭЪЛОН ҚЎШИШ',
                        style: TextStyle(
                            fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5D4037), foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(child: Text(
                    type == 'service'
                        ? '30 кун давомида кўринади • Кунига 5 та эълон'
                        : '3 кун давомида кўринади • Кунига 5 та эълон',
                    style: TextStyle(fontSize: AppText.labelTiny, color: Colors.grey.shade400),
                  )),
                ]),
          ),
        ),
      ),
    );
  }

  // ── Таҳрирлаш ──
  void _showEditDialog(String adId, Map<String, dynamic> oldData) {
    final textCtrl = TextEditingController(text: oldData['text'] ?? '');
    bool isUrgent  = oldData['isUrgent'] == true;
    final type     = oldData['type'] as String? ?? 'work';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),

                  Row(children: [
                    const Icon(Icons.edit, color: _blue, size: 24),
                    const SizedBox(width: 8),
                    const Text('Эълонни таҳрирлаш',
                        style: TextStyle(
                            fontSize: AppText.titleMedium, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 16),

                  // Матн
                  TextField(
                    controller: textCtrl,
                    maxLines: 4, maxLength: 300,
                    decoration: InputDecoration(
                      hintText: 'Эълон матни...',
                      hintStyle: TextStyle(
                          color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                          const BorderSide(color: _blue, width: 1.5)),
                      filled: true, fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Шошилинч — ФАҚАТ "Иш бор" учун
                  if (type == 'work') ...[
                    GestureDetector(
                      onTap: () => setS(() => isUrgent = !isUrgent),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isUrgent
                              ? Colors.red.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isUrgent
                              ? Colors.red.shade300 : Colors.grey.shade300),
                        ),
                        child: Row(children: [
                          Text(isUrgent ? '🚨' : '⏰',
                              style: const TextStyle(fontSize: AppText.titleLarge)),
                          const SizedBox(width: 10),
                          Text('Шошилинч',
                              style: TextStyle(fontSize: AppText.bodyMedium,
                                  fontWeight: FontWeight.w600,
                                  color: isUrgent ? Colors.red : Colors.grey.shade600)),
                          const Spacer(),
                          Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: isUrgent ? Colors.red : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isUrgent
                                  ? Colors.red : Colors.grey.shade400),
                            ),
                            child: isUrgent
                                ? const Icon(Icons.check,
                                color: Colors.white, size: 14)
                                : null,
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Админ учун статус
                  if (_isAdmin) ...[
                    const Text('Статус:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(children: [
                      _statusBtn('active', '✅ Фаол', oldData['status'] == 'active',
                              () => setS(() {})),
                      const SizedBox(width: 8),
                      _statusBtn('completed', '✔️ Ёпилган', oldData['status'] == 'completed',
                              () => setS(() {})),
                      const SizedBox(width: 8),
                      _statusBtn('blocked', '🚫 Блок', oldData['status'] == 'blocked',
                              () => setS(() {})),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // Сақлаш
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Бекор қилиш'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final newText = textCtrl.text.trim();
                          if (newText.isEmpty) return;

                          try {
                            final updates = <String, dynamic>{
                              'text':     newText,
                              'isUrgent': type == 'work' ? isUrgent : false,
                              'editedAt': FieldValue.serverTimestamp(),
                            };

                            if (_isAdmin) {
                              updates['status'] = oldData['status'] ?? 'active';
                            }

                            await _db.collection('ads').doc(adId).update(updates);

                            if (mounted) Navigator.pop(context);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('✅ Эълон янгиланди!'),
                                  backgroundColor: _green,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ));
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Хатолик: $e'),
                                    backgroundColor: Colors.red));
                          }
                        },
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('САҚЛАШ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _statusBtn(String value, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _blue : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(
            fontSize: AppText.labelSmall,
            color: selected ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ── Шикоят ──
  void _showComplaint(String adId) {
    final reasons = [
      '🚫 Алдамчи эълон', '📞 Телефон нотўғри',
      '🗑️ Спам / Такрорий', '⚠️ Ҳақоратли матн',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Шикоят', style: TextStyle(
                  fontSize: AppText.titleMedium, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...reasons.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r, style: const TextStyle(fontSize: AppText.bodyLarge)),
                onTap: () async {
                  await _db.collection('complaints').add({
                    'adId': adId, 'reason': r,
                    'createdAt': FieldValue.serverTimestamp()});
                  if (mounted) Navigator.pop(context);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Шикоят юборилди'),
                    backgroundColor: _green, behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ));
                },
              )),
            ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEBE9),
      appBar: AppBar(
        title: const Text('💼 ИШ ТОП'),
        backgroundColor: const Color(0xFF5D4037),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: '🔨 Иш бор'),
            Tab(text: '🛠️ Хизматлар'),
          ],
        ),
      ),
      body: Column(children: [
        // Қидирув
        Container(
          color: _blue.withOpacity(0.05),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: '🔍 Қидириш...',
              hintStyle:
              TextStyle(color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
              prefixIcon: Icon(Icons.search, color: const Color(0xFF5D4037), size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                  icon: const Icon(Icons.clear,
                      color: Colors.grey, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  })
                  : null,
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
            ),
          ),
        ),

        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildAdsList('work'),
            _buildAdsList('service'),
          ],
        )),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showAddDialog(_tabCtrl.index == 0 ? 'work' : 'service'),
        backgroundColor: const Color(0xFF5D4037), foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Эълон қўшиш',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ── Эълонлар рўйхати ──
  Widget _buildAdsList(String type) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('ads')
          .where('type',   isEqualTo: type)
          .where('status', isEqualTo: 'active')
          .limit(50)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _blue));
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}',
              style: TextStyle(color: Colors.grey.shade500)));
        }

        var docs = snap.data!.docs;

        // Муддати ўтганларни чиқариб ташлаш
        docs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return !_isExpired(data['expiresAt'] as Timestamp?);
        }).toList();

        // Сортировка: шошилинч → createdAt
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aU = aData['isUrgent'] == true ? 0 : 1;
          final bU = bData['isUrgent'] == true ? 0 : 1;
          if (aU != bU) return aU.compareTo(bU);
          final at = aData['createdAt'] as Timestamp?;
          final bt = bData['createdAt'] as Timestamp?;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

        // Қидирув
        if (_searchQuery.isNotEmpty) {
          docs = docs.where((d) {
            final text = ((d.data() as Map<String,dynamic>)['text'] ?? '')
                .toString().toLowerCase();
            return text.contains(_searchQuery);
          }).toList();
        }

        if (docs.isEmpty) {
          return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(type == 'work' ? '🔨' : '🛠️',
                  style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                  _searchQuery.isNotEmpty
                      ? 'Натижа топилмади'
                      : 'Ҳозирча эълонлар йўқ',
                  style: TextStyle(fontSize: AppText.bodyMedium,
                      color: Colors.grey.shade400)),
              const SizedBox(height: 6),
              Text('Биринчи бўлиб эълон қўшинг!',
                  style: TextStyle(fontSize: AppText.bodySmall,
                      color: Colors.grey.shade400)),
            ],
          ));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc  = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _adCard(doc.id, data);
          },
        );
      },
    );
  }

  // ── Эълон карточкаси ──
  Widget _adCard(String id, Map<String, dynamic> data) {
    final isUrgent   = data['isUrgent']     == true;
    final type       = data['type']         as String? ?? 'work';
    final text       = data['text']         as String? ?? '';
    final phone      = data['authorPhone']  as String? ?? '';
    final address    = data['address']      as String? ?? '';
    final authorName = data['authorName']   as String? ?? '';
    final createdAt  = data['createdAt']    as Timestamp?;
    final expiresAt  = data['expiresAt']    as Timestamp?;
    final authorPhone = data['authorPhone'] as String? ?? '';
    final isOwner    = authorPhone == _userPhone; // Ўз эълони

    String expiryStr   = '';
    Color  expiryColor = _green;
    if (expiresAt != null) {
      final left = expiresAt.toDate().difference(DateTime.now());
      if (left.inHours < 12) {
        expiryStr  = '${left.inHours} соат қолди';
        expiryColor = Colors.red;
      } else if (left.inDays < 1) {
        expiryStr  = 'Бугун тугайди';
        expiryColor = Colors.orange;
      } else {
        expiryStr  = '${left.inDays} кун қолди';
        expiryColor = _green;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isUrgent
            ? Border.all(color: Colors.red.shade300, width: 1.5)
            : Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1-қатор
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: type == 'work'
                        ? const Color(0xFF5D4037).withOpacity(0.1) : const Color(0xFF795548).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    type == 'work' ? '🔨 Иш бор' : '🛠️ Хизмат',
                    style: TextStyle(fontSize: AppText.labelTiny, fontWeight: FontWeight.w600,
                        color: type == 'work' ? ModuleTheme.jobTop.primary : ModuleTheme.jobTop.secondary),
                  ),
                ),
                if (isUrgent) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('🚨 Шошилинч',
                        style: TextStyle(fontSize: AppText.labelTiny,
                            fontWeight: FontWeight.w600, color: Colors.red)),
                  ),
                ],
                const Spacer(),
                // Таҳрирлаш тугмаси (эгаси ёки админ)
                if (isOwner || _isAdmin)
                  GestureDetector(
                    onTap: () => _showEditDialog(id, data),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(children: [
                        Icon(Icons.edit, size: 14, color: Color(0xFF5D4037)),
                        SizedBox(width: 4),
                        Text('Таҳрирлаш',
                            style: TextStyle(fontSize: AppText.labelTiny,
                                fontWeight: FontWeight.w600, color: Color(0xFF5D4037))),
                      ]),
                    ),
                  ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showComplaint(id),
                  child: Icon(Icons.more_vert,
                      color: Colors.grey.shade400, size: 18),
                ),
              ]),
              const SizedBox(height: 10),

              // Матн
              Text(text, style: const TextStyle(
                  fontSize: AppText.bodyLarge, height: 1.5, color: Colors.black87)),
              const SizedBox(height: 10),

              // Маълумот — ИСМ КЎРСАТИЛМАЙДИ
              Row(children: [
                if (address.isNotEmpty) ...[
                  Icon(Icons.location_on_outlined,
                      size: 13, color: Colors.grey.shade400),
                  const SizedBox(width: 3),
                  Flexible(child: Text(address,
                      style: TextStyle(
                          fontSize: AppText.labelSmall, color: Colors.grey.shade500),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                ],
                Text(_timeAgo(createdAt), style: TextStyle(
                    fontSize: AppText.labelTiny, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 10),

              // Муддат + Қўнғироқ
              Row(children: [
                if (expiryStr.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: expiryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(expiryStr, style: TextStyle(
                        fontSize: AppText.labelTiny, fontWeight: FontWeight.w600,
                        color: expiryColor)),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    if (phone.isEmpty) return;
                    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
                    final url = Uri(scheme: 'tel', path: cleaned);
                    try {
                      await launchUrl(url,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Телефон: $phone'),
                          backgroundColor: _green,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ));
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFF5D4037),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Row(children: [
                      Icon(Icons.call, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Қўнғироқ', style: TextStyle(
                          fontSize: AppText.bodySmall, fontWeight: FontWeight.bold,
                          color: Colors.white)),
                    ]),
                  ),
                ),
              ]),
            ]),
      ),
    );
  }
}
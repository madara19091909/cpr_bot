import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bg = Color(0xFF070B16);
const _panel = Color(0xFF11182A);
const _cyan = Color(0xFF70D9FF);
const _purple = Color(0xFFB49AFF);

void main() => runApp(const EchoApp());

class EchoApp extends StatelessWidget {
  const EchoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ECHO', debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg, colorScheme: ColorScheme.fromSeed(seedColor: _cyan, brightness: Brightness.dark),
          inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFF0B1120), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
        home: const EchoHome(),
      );
}

class MemoryEntry {
  MemoryEntry({required this.id, required this.title, required this.body, required this.category, required this.createdAt, this.colorIndex = 0});
  final String id; String title; String body; String category; DateTime createdAt; int colorIndex;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body, 'category': category, 'createdAt': createdAt.toIso8601String(), 'colorIndex': colorIndex};
  factory MemoryEntry.fromJson(Map<String, dynamic> j) => MemoryEntry(id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(), title: j['title'] as String? ?? '', body: j['body'] as String? ?? '', category: j['category'] as String? ?? 'فكرة', createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(), colorIndex: j['colorIndex'] as int? ?? 0);
}

class EchoHome extends StatefulWidget { const EchoHome({super.key}); @override State<EchoHome> createState() => _EchoHomeState(); }
class _EchoHomeState extends State<EchoHome> {
  final List<MemoryEntry> _memories = [];
  int _tab = 0; bool _loading = true; String _query = ''; String _category = 'الكل';
  static const _key = 'echo_memories_v1';
  final _categories = const ['فكرة', 'ذكرى', 'هدف', 'شخص', 'ملاحظة'];
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance(); final raw = prefs.getString(_key);
    if (raw != null) { try { final list = jsonDecode(raw) as List<dynamic>; _memories.addAll(list.map((e) => MemoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))); } catch (_) {} }
    if (_memories.isEmpty) {
      _memories.addAll([
        MemoryEntry(id: 'seed1', title: 'بداية عالم ECHO', body: 'أريد مكانًا يجمع أفكاري وذكرياتي بعالم واحد أقدر أكتشفه.', category: 'فكرة', createdAt: DateTime.now().subtract(const Duration(days: 4)), colorIndex: 0),
        MemoryEntry(id: 'seed2', title: 'فكرة تستحق التنفيذ', body: 'الأفكار الصغيرة ممكن تتحول إلى مشاريع كبيرة إذا احتفظت بها ورجعت لها.', category: 'هدف', createdAt: DateTime.now().subtract(const Duration(days: 2)), colorIndex: 1),
        MemoryEntry(id: 'seed3', title: 'لا تنسَ البداية', body: 'سجّل سبب اهتمامك بالمشروع حتى تتذكره بعد فترة.', category: 'ملاحظة', createdAt: DateTime.now(), colorIndex: 2),
      ]);
      await _save();
    }
    if (mounted) setState(() => _loading = false);
  }
  Future<void> _save() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString(_key, jsonEncode(_memories.map((m) => m.toJson()).toList())); }
  List<MemoryEntry> get _filtered => _memories.where((m) => (_category == 'الكل' || m.category == _category) && ('${m.title} ${m.body} ${m.category}'.toLowerCase().contains(_query.toLowerCase()))).toList()..sort((a,b) => b.createdAt.compareTo(a.createdAt));
  Future<void> _openEditor([MemoryEntry? entry]) async {
    final title = TextEditingController(text: entry?.title ?? ''); final body = TextEditingController(text: entry?.body ?? ''); String category = entry?.category ?? 'فكرة';
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: _panel, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))), builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 24), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)))), const SizedBox(height: 20), Text(entry == null ? 'أضف إلى عالمك' : 'عدّل الذكرى', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)), const SizedBox(height: 18),
      TextField(controller: title, autofocus: true, maxLength: 90, decoration: const InputDecoration(labelText: 'العنوان', hintText: 'شنو اللي تريد تتذكره؟')), const SizedBox(height: 10),
      TextField(controller: body, minLines: 4, maxLines: 8, decoration: const InputDecoration(labelText: 'التفاصيل', hintText: 'اكتب فكرتك أو الذكرى هنا...')), const SizedBox(height: 14),
      const Text('التصنيف', style: TextStyle(color: Colors.white70)), const SizedBox(height: 8), Wrap(spacing: 8, children: _categories.map((c) => ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setSheet(() => category = c))).toList()), const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { if (title.text.trim().isEmpty) return; Navigator.pop(ctx, true); }, icon: const Icon(Icons.auto_awesome), label: Text(entry == null ? 'أضف إلى الكون' : 'حفظ التعديلات')))
    ])))));
    if (result == true && mounted) { setState(() { if (entry == null) { _memories.add(MemoryEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), title: title.text.trim(), body: body.text.trim(), category: category, createdAt: DateTime.now(), colorIndex: _memories.length % 4)); } else { entry.title = title.text.trim(); entry.body = body.text.trim(); entry.category = category; } }); await _save(); }
    title.dispose(); body.dispose();
  }
  Future<void> _delete(MemoryEntry m) async { final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('حذف الذكرى؟'), content: Text('راح تنحذف «${m.title}» من جهازك.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))])); if (yes == true) { setState(() => _memories.removeWhere((e) => e.id == m.id)); await _save(); } }
  void _showMemory(MemoryEntry m) { showModalBottomSheet(context: context, backgroundColor: _panel, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx) => Padding(padding: const EdgeInsets.all(22), child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 12,height: 12,decoration: BoxDecoration(color: _nodeColor(m), shape: BoxShape.circle)), const SizedBox(width: 10), Text(m.category, style: const TextStyle(color: Colors.white60)), const Spacer(), IconButton(onPressed: () { Navigator.pop(ctx); _openEditor(m); }, icon: const Icon(Icons.edit_outlined)), IconButton(onPressed: () { Navigator.pop(ctx); _delete(m); }, icon: const Icon(Icons.delete_outline))]), const SizedBox(height: 8), Text(m.title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)), const SizedBox(height: 12), Text(m.body.isEmpty ? 'لا توجد تفاصيل بعد.' : m.body, style: const TextStyle(fontSize: 16, height: 1.7)), const SizedBox(height: 18), Text(_date(m.createdAt), style: const TextStyle(color: Colors.white54)), const SizedBox(height: 20)])))); }
  Color _nodeColor(MemoryEntry m) => [ _cyan, _purple, const Color(0xFFFFC778), const Color(0xFF8BE3C1)][m.colorIndex % 4];
  String _date(DateTime d) => '${d.year}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}';
  @override Widget build(BuildContext context) {
    final pages = [ _universe(), _memoryPage(), _timelinePage(), _discoverPage(), _profilePage() ];
    return Scaffold(body: SafeArea(child: _loading ? const Center(child: CircularProgressIndicator()) : IndexedStack(index: _tab, children: pages)), floatingActionButton: _tab == 4 ? null : FloatingActionButton.extended(onPressed: () => _openEditor(), backgroundColor: _cyan, foregroundColor: _bg, icon: const Icon(Icons.add), label: const Text('ذكرى جديدة')), bottomNavigationBar: NavigationBar(backgroundColor: const Color(0xFF0D1322), indicatorColor: _cyan.withValues(alpha: .15), selectedIndex: _tab, onDestinationSelected: (i) => setState(() { _tab = i; _category = 'الكل'; _query = ''; }), destinations: const [NavigationDestination(icon: Icon(Icons.public), label: 'العالم'), NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'الذاكرة'), NavigationDestination(icon: Icon(Icons.timeline), label: 'الزمن'), NavigationDestination(icon: Icon(Icons.hub_outlined), label: 'الاكتشاف'), NavigationDestination(icon: Icon(Icons.shield_outlined), label: 'ملفي') ]));
  }
  Widget _header(String eyebrow, String title, String subtitle) => Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(eyebrow.toUpperCase(), style: const TextStyle(color: _cyan, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 7), Text(title, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(subtitle, style: const TextStyle(color: Colors.white60, height: 1.4))]));
  Widget _universe() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _header('YOUR PRIVATE UNIVERSE', 'أهلًا بعالمك', 'كل نقطة هنا تحمل فكرة أو لحظة من حياتك.'), Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Container(height: 360, decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), border: Border.all(color: Colors.white.withValues(alpha: .08)), gradient: const RadialGradient(center: Alignment(.1,-.2), radius: 1.1, colors: [Color(0xFF18294B), Color(0xFF0B1122), Color(0xFF070B16)])), child: ClipRRect(borderRadius: BorderRadius.circular(26), child: GestureDetector(onTapUp: (d) { final list = _filtered; if (list.isNotEmpty) _showMemory(list[(d.localPosition.dx / 360 * list.length).floor().clamp(0, list.length-1).toInt()]); }, child: CustomPaint(painter: UniversePainter(_memories), child: Stack(children: [Positioned(left: 16, top: 16, child: _glassPill(Icons.circle, '${_memories.length} نقطة')), Positioned(right: 14, bottom: 14, child: _glassPill(Icons.touch_app_outlined, 'المس نجمة لاكتشافها'))])))))), const SizedBox(height: 18), Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [Expanded(child: _stat('الذكريات', '${_memories.length}', Icons.auto_awesome)), const SizedBox(width: 10), Expanded(child: _stat('المواضيع', '${_memories.map((e) => e.category).toSet().length}', Icons.hub_outlined)), const SizedBox(width: 10), Expanded(child: _stat('هذا الشهر', '${_memories.where((e) => e.createdAt.month == DateTime.now().month && e.createdAt.year == DateTime.now().year).length}', Icons.calendar_month))])), const SizedBox(height: 18), Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [const Expanded(child: Text('أحدث الذكريات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('عرض الكل'))])), Expanded(child: _memories.isEmpty ? _empty('عالمك ينتظر أول ذكرى') : ListView.builder(padding: const EdgeInsets.fromLTRB(16,0,16,90), itemCount: math.min(3, _filtered.length), itemBuilder: (_, i) => _memoryTile(_filtered[i]))) ]);
  Widget _glassPill(IconData icon, String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .28), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .12))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: _cyan), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 11, color: Colors.white70))]));
  Widget _stat(String label, String value, IconData icon) => Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: _cyan, size: 19), const SizedBox(height: 10), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11))]));
  Widget _memoryPage() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_header('MEMORY ARCHIVE', 'ذاكرتك', 'كل أفكارك وذكرياتك بمكان واحد.'), Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: TextField(onChanged: (v) => setState(() => _query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث بذكرياتك...'))), const SizedBox(height: 10), SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), children: ['الكل', ..._categories].map((c) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)))).toList())), const SizedBox(height: 8), Expanded(child: _filtered.isEmpty ? _empty('ما لقينا ذكريات مطابقة') : ListView.builder(padding: const EdgeInsets.fromLTRB(16,0,16,90), itemCount: _filtered.length, itemBuilder: (_, i) => _memoryTile(_filtered[i]))) ]);
  Widget _timelinePage() {
    final list = [..._memories]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final groups = <String, List<MemoryEntry>>{};
    for (final m in list) {
      final key = '${m.createdAt.year} / ${m.createdAt.month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(m);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('TIME TRAVEL', 'رحلتك عبر الزمن', 'ارجع لأي لحظة وشوف شنو كان يشغل بالك.'),
        Expanded(
          child: groups.isEmpty
              ? _empty('أضف أول ذكرى حتى يبدأ خطك الزمني')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                  children: groups.entries.map((g) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.radio_button_checked, color: _cyan, size: 17),
                              const SizedBox(width: 10),
                              Text(g.key, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _cyan)),
                            ],
                          ),
                        ),
                        ...g.value.map((m) => Padding(
                              padding: const EdgeInsets.only(left: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(width: 2, height: 88, color: Colors.white12),
                                  const SizedBox(width: 14),
                                  Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _memoryTile(m, compact: true))),
                                ],
                              ),
                            )),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _discoverPage() {
    final counts = <String, int>{};
    for (final m in _memories) {
      counts[m.category] = (counts[m.category] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final words = <String, int>{};
    for (final m in _memories) {
      for (final w in '${m.title} ${m.body}'.split(RegExp(r'\s+'))) {
        final word = w.replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9]'), '');
        if (word.length >= 4) words[word] = (words[word] ?? 0) + 1;
      }
    }
    final repeated = words.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _header('PATTERNS & CONNECTIONS', 'اكتشف الروابط', 'لمحات بسيطة عن المواضيع المتكررة بعالمك.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.hub, color: _purple, size: 28),
                const SizedBox(height: 12),
                const Text('توزيع ذكرياتك', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('حسب التصنيف الذي اخترته لكل ذكرى.', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 18),
                if (sorted.isEmpty)
                  const Text('أضف ذكريات حتى تظهر الإحصائيات.')
                else
                  ...sorted.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 13),
                        child: Column(
                          children: [
                            Row(children: [Text(e.key), const Spacer(), Text('${e.value}', style: const TextStyle(color: _cyan))]),
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(value: e.value / _memories.length, minHeight: 7, backgroundColor: Colors.white10),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.manage_search, color: _cyan, size: 28),
                const SizedBox(height: 12),
                const Text('كلمات تتكرر', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('اكتشاف محلي بسيط للكلمات المشتركة، وليس تحليلًا دلاليًا بالذكاء الاصطناعي.', style: TextStyle(color: Colors.white54, height: 1.4)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: repeated.take(12).map((e) => Chip(
                    avatar: const Icon(Icons.bubble_chart, size: 15),
                    label: Text('${e.key} · ${e.value}'),
                  )).toList(),
                ),
                if (repeated.isEmpty)
                  const Text('بعد ماكو كلمات متكررة كفاية.', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 90),
      ],
    );
  }
  Widget _profilePage() => ListView(padding: EdgeInsets.zero, children: [_header('YOUR SPACE', 'مساحتك الخاصة', 'عالمك محفوظ على هذا الجهاز.'), Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1B3150), Color(0xFF17152E)]), borderRadius: BorderRadius.circular(24)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.shield_moon_outlined, color: _cyan, size: 34), SizedBox(height: 14), Text('خصوصيتك أولًا', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), SizedBox(height: 8), Text('الذكريات محفوظة محليًا على جهازك باستخدام تخزين التطبيق. ماكو حساب ولا مزامنة ولا خادم خارجي.', style: TextStyle(color: Colors.white70, height: 1.6))]))), const SizedBox(height: 14), Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Container(decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(20)), child: Column(children: [ListTile(leading: const Icon(Icons.auto_awesome, color: _purple), title: const Text('عدد الذكريات'), trailing: Text('${_memories.length}')), const Divider(height: 1, indent: 56), const ListTile(leading: Icon(Icons.storage_outlined, color: _cyan), title: Text('التخزين'), subtitle: Text('محلي على الجهاز فقط')), const Divider(height: 1, indent: 56), const ListTile(leading: Icon(Icons.wifi_off_outlined, color: Color(0xFF8BE3C1)), title: Text('الاتصال'), subtitle: Text('الميزات الأساسية تعمل بدون إنترنت'))]))), const SizedBox(height: 14), Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: OutlinedButton.icon(onPressed: () async { await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('بيانات عالمك'), content: const Text('ميزة التصدير إلى ملف خارجي ستضاف لاحقًا. بياناتك الحالية محفوظة داخل التطبيق على جهازك.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام'))])); }, icon: const Icon(Icons.info_outline), label: const Text('معلومات عن بياناتك'))), const SizedBox(height: 90)]);
  Widget _memoryTile(MemoryEntry m, {bool compact = false}) => Card(color: _panel, margin: const EdgeInsets.only(bottom: 9), child: ListTile(onTap: () => _showMemory(m), leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: _nodeColor(m).withValues(alpha: .13), borderRadius: BorderRadius.circular(14)), child: Icon(_iconFor(m.category), color: _nodeColor(m))), title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(compact ? _date(m.createdAt) : '${m.category}  •  ${_date(m.createdAt)}\n${m.body}', maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, height: 1.5)), trailing: const Icon(Icons.chevron_left, color: Colors.white38), isThreeLine: !compact));
  IconData _iconFor(String c) => switch (c) { 'ذكرى' => Icons.favorite_outline, 'هدف' => Icons.flag_outlined, 'شخص' => Icons.person_outline, 'ملاحظة' => Icons.sticky_note_2_outlined, _ => Icons.lightbulb_outline };
  Widget _empty(String text) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.auto_awesome, size: 38, color: _cyan), const SizedBox(height: 12), Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))])));
}

class UniversePainter extends CustomPainter {
  UniversePainter(this.memories); final List<MemoryEntry> memories;
  @override void paint(Canvas canvas, Size size) {
    final random = math.Random(23); final center = Offset(size.width*.52, size.height*.48);
    final starPaint = Paint()..color = Colors.white.withValues(alpha: .35);
    for (int i=0;i<100;i++) { final p = Offset(random.nextDouble()*size.width, random.nextDouble()*size.height); canvas.drawCircle(p, random.nextDouble()*1.2+.25, starPaint); }
    final count = memories.length.clamp(0, 36); if (count == 0) return;
    final points = <Offset>[]; final colors = [ _cyan, _purple, const Color(0xFFFFC778), const Color(0xFF8BE3C1) ];
    for (int i=0;i<count;i++) { final angle = i*2.39996; final radius = 26.0 + math.sqrt(i+1)*math.min(size.width,size.height)*.095; points.add(Offset(center.dx+math.cos(angle)*radius, center.dy+math.sin(angle)*radius*.72)); }
    final line = Paint()..color = _cyan.withValues(alpha: .16)..strokeWidth = 1;
    for (int i=0;i<points.length;i++) { for (int j=i+1;j<points.length;j++) { if ((points[i]-points[j]).distance < size.width*.28) canvas.drawLine(points[i],points[j],line); } }
    for (int i=0;i<points.length;i++) { final p=points[i]; final color=colors[memories[i].colorIndex%colors.length]; canvas.drawCircle(p, 13, Paint()..color=color.withValues(alpha: .10)); canvas.drawCircle(p, 5.0+(i%3), Paint()..color=color.withValues(alpha: .9)); canvas.drawCircle(p, 2, Paint()..color=Colors.white.withValues(alpha: .9)); }
    final glow = Paint()..shader = RadialGradient(colors: [_cyan.withValues(alpha: .22), _purple.withValues(alpha: .06), Colors.transparent]).createShader(Rect.fromCircle(center:center,radius:72)); canvas.drawCircle(center,72,glow); canvas.drawCircle(center,22,Paint()..color=_cyan.withValues(alpha: .06)); canvas.drawCircle(center,8,Paint()..color=_cyan.withValues(alpha: .65)); canvas.drawCircle(center,3,Paint()..color=Colors.white);
    final tp = TextPainter(text: const TextSpan(text:'ECHO',style:TextStyle(color:Colors.white70,fontSize:10,fontWeight:FontWeight.bold,letterSpacing:2)),textDirection:TextDirection.ltr)..layout(); tp.paint(canvas,center+const Offset(-17,16));
  }
  @override bool shouldRepaint(covariant UniversePainter oldDelegate) => oldDelegate.memories != memories || oldDelegate.memories.length != memories.length;
}

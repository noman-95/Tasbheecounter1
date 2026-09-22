import 'package:flutter/material.dart';

import '../services/storage_service.dart';

class QuranHistoryScreen extends StatefulWidget {
  const QuranHistoryScreen({super.key});

  @override
  State<QuranHistoryScreen> createState() => _QuranHistoryScreenState();
}

class _QuranHistoryScreenState extends State<QuranHistoryScreen> {
  static const Color primaryGreen = Color(0xFF087F5B);

  List<Map<String, dynamic>> _history = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final history = await StorageService.getQuranHistory();
    if (!mounted) return;
    setState(() {
      _history = history;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    if (_history.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Quran History'),
        content: const Text('Quran recitation history clear kar dein?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await StorageService.clearQuranHistory();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Quran Recitation History'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear history',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : _history.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Abhi Quran recitation history nahi hai.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: primaryGreen,
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      final correct = int.tryParse(item['correctWords']?.toString() ?? '') ?? 0;
                      final wrong = int.tryParse(item['wrongWords']?.toString() ?? '') ?? 0;
                      final total = int.tryParse(item['totalWords']?.toString() ?? '') ?? (correct + wrong);
                      final surah = item['surahName']?.toString() ?? '';
                      final surahNumber = item['surahNumber']?.toString() ?? '';
                      final ayah = item['ayahNumber']?.toString() ?? '';
                      final attempts = int.tryParse(item['attemptCount']?.toString() ?? '') ?? 1;
                      final rawWords = item['wordStatuses'];
                      final words = rawWords is List
                          ? rawWords
                              .whereType<Map>()
                              .map((e) => Map<String, dynamic>.from(e))
                              .toList(growable: false)
                          : const <Map<String, dynamic>>[];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: primaryGreen.withOpacity(0.12),
                            child: const Icon(Icons.menu_book_rounded, color: primaryGreen),
                          ),
                          title: Text('$surah • Ayah $ayah'),
                          subtitle: Text(
                            'Surah $surahNumber  •  $correct/$total sahi  •  $wrong ghalat  •  $attempts attempt',
                          ),
                          trailing: Icon(
                            wrong == 0 ? Icons.check_circle : Icons.info_outline,
                            color: wrong == 0 ? Colors.green : Colors.orange,
                          ),
                          children: [
                            if (words.isEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('Is purani entry mein lafzon ki detail save nahi hui thi.'),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 6,
                                    runSpacing: 7,
                                    children: words.map((word) {
                                      final status = word['status']?.toString() ?? 'pending';
                                      final isCorrect = status == 'correct';
                                      final isImprove = status == 'improve';
                                      final bg = isCorrect
                                          ? Colors.green.shade50
                                          : isImprove
                                              ? Colors.orange.shade50
                                              : Colors.red.shade50;
                                      final fg = isCorrect
                                          ? Colors.green.shade800
                                          : isImprove
                                              ? Colors.orange.shade900
                                              : Colors.red.shade800;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: bg,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: fg.withOpacity(0.18)),
                                        ),
                                        child: Text(
                                          word['word']?.toString() ?? '',
                                          style: TextStyle(fontSize: 20, color: fg, fontWeight: FontWeight.w600),
                                        ),
                                      );
                                    }).toList(growable: false),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

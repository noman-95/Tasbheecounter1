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

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: primaryGreen.withOpacity(0.12),
                            child: const Icon(Icons.menu_book_rounded, color: primaryGreen),
                          ),
                          title: Text('$surah • Ayah $ayah'),
                          subtitle: Text(
                            'Surah $surahNumber  •  $correct/$total words sahi  •  $wrong ghalat',
                          ),
                          trailing: Icon(
                            wrong == 0 ? Icons.check_circle : Icons.info_outline,
                            color: wrong == 0 ? Colors.green : Colors.orange,
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

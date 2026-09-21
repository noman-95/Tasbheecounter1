import 'package:flutter/material.dart';

import '../models/surah_model.dart';
import '../services/quran_service.dart';
import '../services/storage_service.dart';
import 'surah_screen.dart';
import 'quran_history_screen.dart';

class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  static const Color primaryGreen = Color(0xFF087F5B);
  final TextEditingController _searchController = TextEditingController();
  late final Future<void> _quranFuture;
  String _query = '';
  int? _lastSurahNumber;
  int _lastSurahProgress = 0;
  String _selectedScript = 'Uthmani';

  @override
  void initState() {
    super.initState();
    _quranFuture = _prepare();
  }

  Future<void> _prepare() async {
    await QuranService.loadQuran();
    final lastSurah = await StorageService.getLastQuranSurah();
    _selectedScript = await StorageService.getQuranScript();
    if (lastSurah != null) {
      _lastSurahNumber = lastSurah;
      _lastSurahProgress = await StorageService.getQuranProgress(lastSurah);
    }
  }


  Widget _buildLearningHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0B8F68), Color(0xFF064E3B)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [BoxShadow(color: const Color(0xFF087F5B).withOpacity(.20), blurRadius: 20, offset: const Offset(0, 9))],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Your Quran Journey', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            SizedBox(height: 6),
            Text('Choose a Surah and start your next recitation session.', style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 11.5, height: 1.4)),
          ])),
          Container(width: 62, height: 62, decoration: BoxDecoration(color: Colors.white.withOpacity(.14), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 29)),
        ]),
      ),
    );
  }

  Widget _buildResumeCard() {
    final surah = QuranService.getSurah(_lastSurahNumber!);
    if (surah == null) return const SizedBox.shrink();

    final completed = _lastSurahProgress.clamp(0, surah.ayahCount).toInt();
    final progress = surah.ayahCount == 0 ? 0.0 : completed / surah.ayahCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Card(
        elevation: 0,
        color: const Color(0xFFEAF6F0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SurahScreen(surah: surah)),
            );
            final last = await StorageService.getLastQuranSurah();
            if (last != null && mounted) {
              setState(() {
                _lastSurahNumber = last;
              });
              _lastSurahProgress = await StorageService.getQuranProgress(last);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFF087F5B), borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Continue Learning', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF17382E))),
                      const SizedBox(height: 3),
                      Text('${surah.transliteration} • ${completed}/${surah.ayahCount} Ayahs', style: const TextStyle(fontSize: 12, color: Color(0xFF5D7168))),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white, valueColor: const AlwaysStoppedAnimation(Color(0xFF087F5B))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF087F5B)),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildScriptSelector() {
    final isIndo = _selectedScript == 'Indo-Pak';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B8F68), Color(0xFF075C45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: const Color(0xFF087F5B).withOpacity(.20), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: Colors.white.withOpacity(.14), borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.auto_stories_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quran Script', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text('Choose your preferred Arabic script', style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 11)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            initialValue: null,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) async {
              setState(() => _selectedScript = value);
              await StorageService.saveQuranScript(value);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'Uthmani', child: Text('Uthmani Hafs')),
              PopupMenuItem(value: 'Indo-Pak', child: Text('Indo-Pak')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Text(isIndo ? 'Indo-Pak' : 'Uthmani', style: const TextStyle(color: Color(0xFF14543F), fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(width: 3),
                const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF14543F), size: 18),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF5F8F6),
        foregroundColor: const Color(0xFF17382E),
        titleSpacing: 18,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quran Learning', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            SizedBox(height: 2),
            Text('Read • Listen • Recite • Improve', style: TextStyle(fontSize: 10.5, color: Color(0xFF718078), fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QuranHistoryScreen()),
              );
            },
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Quran Recitation History',
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _quranFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: primaryGreen),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Quran data load nahi ho saka.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final surahs = QuranService.getSurahs();
          final filtered = surahs.where((surah) {
            final query = _query.trim().toLowerCase();
            if (query.isEmpty) return true;
            return surah.number.toString() == query ||
                surah.transliteration.toLowerCase().contains(query) ||
                surah.nameArabic.contains(_query.trim());
          }).toList(growable: false);

          return Column(
            children: [
              _buildLearningHero(),
              if (_lastSurahNumber != null) _buildResumeCard(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: _buildScriptSelector(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Surah search karein...',
                    prefixIcon: const Icon(Icons.search, color: primaryGreen),
                    suffixIcon: _query.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Koi Surah nahi mili.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final surah = filtered[index];
                          return _SurahCard(surah: surah);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SurahCard extends StatelessWidget {
  final SurahModel surah;

  const _SurahCard({required this.surah});

  static const Color primaryGreen = Color(0xFF087F5B);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SurahScreen(surah: surah)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${surah.number}',
                  style: const TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      surah.transliteration,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${surah.nameEnglish} • ${surah.ayahCount} Ayahs',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${surah.revelationPlace} • Revelation Order: ${surah.revelationOrder}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                surah.nameArabic,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

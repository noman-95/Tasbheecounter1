import 'package:flutter/material.dart';

import '../models/ayah_model.dart';
import '../models/surah_model.dart';
import '../services/quran_service.dart';
import '../services/quran_audio_service.dart';
import '../services/storage_service.dart';
import 'recitation_screen.dart';

class SurahScreen extends StatefulWidget {
  final SurahModel surah;

  const SurahScreen({
    super.key,
    required this.surah,
  });

  @override
  State<SurahScreen> createState() => _SurahScreenState();
}

class _SurahScreenState extends State<SurahScreen> {
  static const Color primaryGreen = Color(0xFF087F5B);
  TranslationLanguage selectedLanguage = TranslationLanguage.urdu;
  late final Future<void> _quranFuture;
  int _lastCompletedAyah = 0;
  bool _progressLoading = true;
  String _selectedScript = 'Uthmani';

  @override
  void initState() {
    super.initState();
    _quranFuture = _prepare();
    _loadProgress();
  }

  Future<void> _prepare() async {
    await QuranService.loadQuran();
    _selectedScript = await StorageService.getQuranScript();
  }

  Future<void> _loadProgress() async {
    final value = await StorageService.getQuranProgress(widget.surah.number);
    if (!mounted) return;
    setState(() {
      _lastCompletedAyah = value;
      _progressLoading = false;
    });
  }

  int get _resumeAyahIndex {
    if (widget.surah.ayahCount <= 0) return 0;
    // Progress stores the number of completed ayahs. Resume from the next ayah.
    if (_lastCompletedAyah >= widget.surah.ayahCount) {
      return widget.surah.ayahCount - 1;
    }
    return _lastCompletedAyah.clamp(0, widget.surah.ayahCount - 1).toInt();
  }

  Future<void> _openRecitation(int ayahIndex) async {
    await StorageService.saveLastQuranSurah(widget.surah.number);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecitationScreen(
          selectedSurah: widget.surah,
          initialAyahIndex: ayahIndex,
        ),
      ),
    );
    await _loadProgress();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: Text(widget.surah.transliteration),
        actions: [
          IconButton(
            tooltip: 'Offline Surah Audio',
            onPressed: () async {
              final ayahs = QuranService.getAyahs(widget.surah.number);
              await _downloadSurahAudio(ayahs);
            },
            icon: const Icon(Icons.download_for_offline_rounded),
          ),
          IconButton(
            tooltip: 'AI Recitation Check',
            onPressed: () => _openRecitation(_resumeAyahIndex),
            icon: const Icon(Icons.mic_rounded),
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
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final ayahs = QuranService.getAyahs(widget.surah.number);
          return Column(
            children: [
              _buildHeader(),
              _buildProgressCard(),
              _buildScriptSelector(),
              _buildLanguageSelector(),
              Expanded(child: _buildAyahs(ayahs)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _downloadSurahAudio(List<AyahModel> ayahs) async {
    if (ayahs.isEmpty) return;

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Offline Quran Audio'),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Is Surah ka audio download ho raha hai...')),
          ],
        ),
      ),
    );

    try {
      await QuranAudioService.downloadSurah(
        ayahs,
        widget.surah.number,
      );
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio download failed: $e')),
        );
      }
      return;
    }

    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Is Surah ka audio offline save ho gaya.'),
        ),
      );
    }
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: primaryGreen.withOpacity(0.08),
      child: Column(
        children: [
          Text(
            widget.surah.nameArabic,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: _selectedScript == 'Indo-Pak' ? 'IndoPak' : 'UthmanicHafs',
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.surah.nameEnglish,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.surah.revelationPlace} • ${widget.surah.ayahCount} Ayahs',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    if (_progressLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }

    final completed = _lastCompletedAyah
        .clamp(0, widget.surah.ayahCount)
        .toInt();
    final finished = completed >= widget.surah.ayahCount && widget.surah.ayahCount > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        elevation: 0,
        color: primaryGreen.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.bookmark_rounded, color: primaryGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  finished
                      ? 'Progress complete • ${widget.surah.ayahCount}/${widget.surah.ayahCount} Ayahs'
                      : 'Progress saved • $completed/${widget.surah.ayahCount} Ayahs',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: widget.surah.ayahCount == 0
                    ? null
                    : () => _openRecitation(_resumeAyahIndex),
                child: Text(finished ? 'Review' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildScriptSelector() {
    final isIndo = _selectedScript == 'Indo-Pak';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F7F4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E9E1)),
        ),
        child: Row(children: [
          const Icon(Icons.translate_rounded, color: primaryGreen, size: 20),
          const SizedBox(width: 9),
          const Expanded(child: Text('Quran Script', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF17382E)))),
          ChoiceChip(
            label: const Text('Uthmani'),
            selected: !isIndo,
            onSelected: (_) async {
              setState(() => _selectedScript = 'Uthmani');
              await StorageService.saveQuranScript('Uthmani');
            },
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Indo-Pak'),
            selected: isIndo,
            onSelected: (_) async {
              setState(() => _selectedScript = 'Indo-Pak');
              await StorageService.saveQuranScript('Indo-Pak');
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ChoiceChip(
              label: const SizedBox(
                width: double.infinity,
                child: Center(child: Text('English')),
              ),
              selected: selectedLanguage == TranslationLanguage.english,
              selectedColor: primaryGreen.withOpacity(0.2),
              onSelected: (_) {
                setState(() => selectedLanguage = TranslationLanguage.english);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ChoiceChip(
              label: const SizedBox(
                width: double.infinity,
                child: Center(
                  child: Text('اردو', textDirection: TextDirection.rtl),
                ),
              ),
              selected: selectedLanguage == TranslationLanguage.urdu,
              selectedColor: primaryGreen.withOpacity(0.2),
              onSelected: (_) {
                setState(() => selectedLanguage = TranslationLanguage.urdu);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAyahs(List<AyahModel> ayahs) {
    if (ayahs.isEmpty) {
      return const Center(
        child: Text('Ayahs are not available yet.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: ayahs.length,
      itemBuilder: (context, index) {
        final ayah = ayahs[index];
        final isUrdu = selectedLanguage == TranslationLanguage.urdu;

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ayah.arabic,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: _selectedScript == 'Indo-Pak' ? 'IndoPak' : 'UthmanicHafs',
                    fontSize: 27,
                    height: 1.8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  ayah.getTranslation(selectedLanguage),
                  textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  textAlign: isUrdu ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.7,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: primaryGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${ayah.numberInSurah}',
                        style: const TextStyle(
                          color: primaryGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _openRecitation(index),
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Recite & Check'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

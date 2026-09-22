import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/ayah_model.dart';
import '../models/surah_model.dart';
import '../services/quran_service.dart';
import '../services/quran_audio_service.dart';
import '../services/storage_service.dart';
import '../services/qrc_online_service.dart';

class RecitationScreen extends StatefulWidget {
  final SurahModel selectedSurah;
  final int initialAyahIndex;

  const RecitationScreen({
    super.key,
    required this.selectedSurah,
    this.initialAyahIndex = 0,
  });

  @override
  State<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends State<RecitationScreen> {
  static const Color primaryGreen = Color(0xFF087F5B);

  late final Future<void> _quranFuture;

  List<AyahModel> _ayahs = const [];

  int _currentAyahIndex = 0;

  bool _isListening = false;
  bool _isEvaluated = false;
  bool _finishing = false;

  bool _audioBusy = false;
  bool _audioDownloaded = false;
  bool _audioPlaying = false;
  bool _usingOnlineQrc = false;
  QrcOnlineService? _qrcService;
  Map<String, dynamic>? _latestQrcResult;
  Timer? _transcriptUiTimer;
  String _pendingTranscriptUi = '';
  Timer? _liveHistoryTimer;
  int _liveHistoryGeneration = 0;

  String _spokenText = '';
  String _message = 'Mic dabayein aur poori ayat parhein.';
  String _selectedScript = 'Uthmani';

  List<_WordResult> _results = const [];
  bool _retryMode = false;
  List<int> _retryWordIndexes = const [];

  int _sessionToken = 0;
  int? _savedSessionToken;

  @override
  void initState() {
    super.initState();

    _quranFuture = _prepare();
  }

  Future<void> _prepare() async {
    await StorageService.saveLastQuranSurah(widget.selectedSurah.number);
    await QuranService.loadQuran();
    _selectedScript = await StorageService.getQuranScript();

    _ayahs = QuranService.getAyahs(
      widget.selectedSurah.number,
    );

    if (_ayahs.isEmpty) {
      return;
    }

    _currentAyahIndex = widget.initialAyahIndex
        .clamp(0, _ayahs.length - 1)
        .toInt();

    await _refreshAudioState();
    await _restoreSavedAyahFeedback();

  }

  @override
  void dispose() {
    _transcriptUiTimer?.cancel();
    _liveHistoryTimer?.cancel();
    _qrcService?.dispose();
    QuranAudioService.stop();
    super.dispose();
  }

  AyahModel? get _currentAyah {
    if (_ayahs.isEmpty) {
      return null;
    }

    if (_currentAyahIndex >= _ayahs.length) {
      return null;
    }

    return _ayahs[_currentAyahIndex];
  }

  Future<void> _restoreSavedAyahFeedback() async {
    final ayah = _currentAyah;
    if (ayah == null) return;
    try {
      final history = await StorageService.getQuranHistory();
      Map<String, dynamic>? item;
      for (final entry in history) {
        if (entry['surahNumber']?.toString() == widget.selectedSurah.number.toString() &&
            entry['ayahNumber']?.toString() == ayah.numberInSurah.toString()) {
          item = entry;
          break;
        }
      }
      if (item == null || !mounted) return;
      final raw = item!['wordStatuses'];
      if (raw is! List) return;
      final restored = raw.whereType<Map>().map((e) {
        final word = e['word']?.toString() ?? '';
        final statusName = e['status']?.toString() ?? 'pending';
        final status = _WordStatus.values.firstWhere(
          (value) => value.name == statusName,
          orElse: () => _WordStatus.pending,
        );
        return _WordResult(word, status);
      }).toList(growable: false);
      if (restored.length == _splitWords(ayah.arabic).length) {
        setState(() {
          _results = restored;
          _isEvaluated = true;
          _message = 'Pichli practice ki word-by-word history restore ho gayi.';
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshAudioState() async {
    final ayah = _currentAyah;

    if (ayah == null) {
      return;
    }

    try {
      final downloaded =
          await QuranAudioService.isDownloaded(
        ayah,
        widget.selectedSurah.number,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _audioDownloaded = downloaded;
      });
    } catch (_) {}
  }

  Future<void> _playAudio() async {
    final ayah = _currentAyah;

    if (ayah == null || _audioBusy) {
      return;
    }

    setState(() {
      _audioBusy = true;
      _audioPlaying = true;
      _message =
          'Qari ki tilawat chal rahi hai. Phir apni ayat parhein.';
    });

    try {
      await QuranAudioService.play(
        ayah,
        widget.selectedSurah.number,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _audioDownloaded = true;
        _message =
            'Qari ki tilawat sun rahe hain. Phir apni ayat parhein.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _audioPlaying = false;
        _message = 'Audio play nahi ho saka: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _audioBusy = false;
        });
      }
    }
  }

  Future<void> _stopAudio() async {
    await QuranAudioService.stop();

    if (!mounted) {
      return;
    }

    setState(() {
      _audioPlaying = false;
      _message =
          'Mic dabayein aur poori ayat parhein.';
    });
  }

  Future<void> _downloadCurrentAudio() async {
    final ayah = _currentAyah;

    if (ayah == null || _audioBusy) {
      return;
    }

    setState(() {
      _audioBusy = true;
      _message =
          'Ayah ka audio offline save ho raha hai...';
    });

    try {
      await QuranAudioService.download(
        ayah,
        widget.selectedSurah.number,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _audioDownloaded = true;
        _message =
            'Audio offline save ho gaya. Ab internet ke baghair sun sakte hain.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message =
            'Audio download nahi hua: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _audioBusy = false;
        });
      }
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _finishListening();
    } else {
      await _startListening();
    }
  }

  Future<bool> _startOnlineQrc(AyahModel ayah) async {
    final service = QrcOnlineService();
    if (!service.configured) return false;

    final started = await service.start(
      chapterIndex: widget.selectedSurah.number,
      verseIndex: ayah.numberInSurah,
      wordIndex: (_retryWordIndexes.isNotEmpty ? _retryWordIndexes.first + 1 : 1),
      hafzLevel: 1,
      tajweedLevel: 3,
    );
    if (!started) {
      await service.dispose();
      return false;
    }

    _qrcService = service;
    _usingOnlineQrc = true;
    _latestQrcResult = null;
    service.results.listen((result) {
      if (!mounted || !_usingOnlineQrc) return;
      final event = result['event']?.toString();
      if (event == 'TILAWA_RESULT') {
        _latestQrcResult = result;
        _applyQrcResult(result, persist: false);
        final text = result['text']?.toString();
        if (text != null && text.trim().isNotEmpty) {
          _spokenText = text.trim();
        }
      }
      if (event == 'SANAD_ERROR') {
        if (mounted) setState(() => _message = result['message']?.toString() ?? 'Tajweed server error.');
      }
    });
    return true;
  }

  void _applyQrcResult(Map<String, dynamic> result, {required bool persist}) {
    final ayah = _currentAyah;
    if (ayah == null) return;
    if (result['event'] == 'SANAD_ERROR') {
      if (mounted) setState(() => _message = result['message']?.toString() ?? 'Tajweed server error.');
      return;
    }

    final expectedWords = _splitWords(ayah.arabic);
    final current = _results.length == expectedWords.length
        ? List<_WordResult>.from(_results)
        : expectedWords.map((w) => _WordResult(w, _WordStatus.pending)).toList();

    final wordScores = result['word_scores'];
    if (wordScores is List) {
      for (final raw in wordScores) {
        if (raw is! Map) continue;
        final start = int.tryParse(raw['start_idx']?.toString() ?? '');
        final end = int.tryParse(raw['end_idx']?.toString() ?? '');
        final word = raw['word']?.toString() ?? '';
        final verdict = raw['verdict']?.toString() ?? '';
        var index = -1;
        if (start != null && end != null) {
          final expected = expectedWords;
          var cursor = 0;
          for (var i = 0; i < expected.length; i++) {
            final next = cursor + expected[i].length;
            if (start >= cursor && start < next) { index = i; break; }
            cursor = next + 1;
          }
        }
        if (index < 0 && word.isNotEmpty) {
          index = expectedWords.indexWhere((w) => _normalizeArabic(w) == _normalizeArabic(word));
        }
        if (index < 0 || index >= current.length) continue;
        final status = switch (verdict) {
          'green' => _WordStatus.correct,
          'yellow' => _WordStatus.improve,
          'red' => _WordStatus.wrong,
          _ => current[index].status,
        };
        current[index] = _WordResult(expectedWords[index], status);
      }
    } else {
      // Backward-compatible mapping for an older QRC response, if encountered.
      final correct = <String>{};
      final skipped = <String>{};
      final tajweed = <String>{};
      for (final item in (result['correct_words'] as List? ?? const [])) {
        if (item is Map) correct.add('${item['chapter']}:${item['verse']}:${item['word']}');
      }
      for (final item in (result['skipped_words'] as List? ?? const [])) {
        if (item is Map) skipped.add('${item['chapter']}:${item['verse']}:${item['word']}');
      }
      for (final item in (result['tajweed_mistakes'] as List? ?? const [])) {
        if (item is Map) tajweed.add('${item['chapter']}:${item['verse']}:${item['word']}');
      }
      for (var i = 0; i < expectedWords.length; i++) {
        final k = '${widget.selectedSurah.number}:${ayah.numberInSurah}:${i + 1}';
        if (skipped.contains(k)) current[i] = _WordResult(expectedWords[i], _WordStatus.wrong);
        else if (tajweed.contains(k)) current[i] = _WordResult(expectedWords[i], _WordStatus.improve);
        else if (correct.contains(k)) current[i] = _WordResult(expectedWords[i], _WordStatus.correct);
      }
    }

    final contentStatus = result['content_status']?.toString();
    if (contentStatus == 'content_mismatch') {
      if (mounted) setState(() => _message = 'Recitation ayat se match nahi hui. Tajweed score nahi diya gaya.');
      return;
    }

    final correctCount = current.where((x) => x.status == _WordStatus.correct).length;
    final improveCount = current.where((x) => x.status == _WordStatus.improve).length;
    final wrongCount = current.where((x) => x.status == _WordStatus.wrong).length;
    if (!mounted) return;
    setState(() {
      _results = List.unmodifiable(current);
      _isEvaluated = current.any((x) => x.status != _WordStatus.pending);
      _message = 'Online Tajweed: $correctCount sahi, $improveCount Tajweed review, $wrongCount dobara.';
    });
    _scheduleLiveHistorySave(current);
    if (persist) _saveCurrentResults(current);
  }

  Future<void> _saveCurrentResults(List<_WordResult> results) async {
    final ayah = _currentAyah;
    if (ayah == null) return;
    final correct = results.where((x) => x.status == _WordStatus.correct).length;
    final wrong = results.where((x) => x.status != _WordStatus.correct).length;
    await StorageService.saveOrUpdateQuranHistory(
      surahNumber: widget.selectedSurah.number,
      surahName: widget.selectedSurah.transliteration,
      ayahNumber: ayah.numberInSurah,
      correctWords: correct,
      wrongWords: wrong,
      wordStatuses: results.map((x) => {'word': x.word, 'status': x.status.name}).toList(growable: false),
    );
  }

  int _globalWordOffsetForAyah(int ayahIndex) {
    var offset = 0;
    for (var i = 0; i < ayahIndex && i < _ayahs.length; i++) {
      offset += _splitWords(_ayahs[i].arabic).length;
    }
    return offset;
  }

  Future<void> _startListening() async {
    final ayah = _currentAyah;
    if (ayah == null || _isListening || _finishing) return;

    await QuranAudioService.stop();
    if (mounted) setState(() => _audioPlaying = false);

    _sessionToken = DateTime.now().microsecondsSinceEpoch;
    _savedSessionToken = null;
    _spokenText = '';

    // IMPORTANT: starting the microphone must never reset an already-evaluated ayah.
    // Existing word statuses are preserved and only the words returned by the
    // online engine are updated.
    final previousResults = List<_WordResult>.from(_results);
    final fullWords = _splitWords(ayah.arabic);
    final retryIndexes = _results.length == fullWords.length
        ? List<int>.generate(fullWords.length, (i) => i)
            .where((i) => _results[i].status != _WordStatus.correct)
            .toList()
        : <int>[];
    _retryMode = retryIndexes.isNotEmpty;
    _retryWordIndexes = List.unmodifiable(retryIndexes);
    final targetWords = _retryMode
        ? retryIndexes.map((i) => fullWords[i]).join(' ')
        : ayah.arabic;

    // Online Tajweed is now the ONLY recitation-analysis path.
    // No offline ASR/Tajweed fallback is used, because it can produce weaker
    // Tajweed judgments and inconsistent word coloring.
    try {
      if (mounted) {
        setState(() {
          _isListening = true;
          _isEvaluated = false;
          _results = List.unmodifiable(previousResults);
          _message = _retryMode
              ? 'Online Tajweed AI — sirf red/orange lafz parhein: $targetWords'
              : 'Online Tajweed AI connect ho raha hai...';
        });
      }

      final started = await _startOnlineQrc(ayah);
      if (!started) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _message = 'Online Tajweed ke liye internet aur API access zaroori hai.';
          });
        }
      } else if (mounted) {
        setState(() {
          _message = _retryMode
              ? 'Online Tajweed AI — sirf red/orange lafz parhein.'
              : 'Online Tajweed AI Listening...';
        });
      }
    } catch (e) {
      _usingOnlineQrc = false;
      _isListening = false;
      if (mounted) {
        setState(() {
          _message = 'Online Tajweed service start nahi hui. Internet/API key check karein.';
        });
      }
    }
  }

  void _scheduleLiveHistorySave(List<_WordResult> results) {
    _liveHistoryTimer?.cancel();
    final generation = ++_liveHistoryGeneration;
    final snapshot = List<_WordResult>.unmodifiable(results);
    _liveHistoryTimer = Timer(const Duration(milliseconds: 650), () async {
      if (!mounted || generation != _liveHistoryGeneration) return;
      final ayah = _currentAyah;
      if (ayah == null || snapshot.isEmpty) return;
      final correct = snapshot.where((x) => x.status == _WordStatus.correct).length;
      final wrong = snapshot.where((x) => x.status != _WordStatus.correct).length;
      await StorageService.saveOrUpdateQuranHistory(
        surahNumber: widget.selectedSurah.number,
        surahName: widget.selectedSurah.transliteration,
        ayahNumber: ayah.numberInSurah,
        correctWords: correct,
        wrongWords: wrong,
        wordStatuses: snapshot.map((x) => {'word': x.word, 'status': x.status.name}).toList(growable: false),
      );
    });
  }

  Future<void> _finishListening() async {
    if (!_isListening || _finishing) return;
    _finishing = true;
    _sessionToken++; // invalidate late speech callbacks immediately
    if (mounted) {
      setState(() {
        _isListening = false;
        _message = 'Recitation complete — text analysis ho rahi hai...';
      });
    }

    try {
      if (_usingOnlineQrc) {
        final finalResult = await _qrcService?.stop();
        if (finalResult != null) {
          _latestQrcResult = finalResult;
          _applyQrcResult(finalResult, persist: true);
        } else if (_latestQrcResult != null) {
          _applyQrcResult(_latestQrcResult!, persist: true);
        }
        _spokenText = _spokenText.trim();
        // QRC is authoritative for online sessions; do not run the old
        // local text aligner afterwards and overwrite Tajweed results.
        return;
      }

      final text = _spokenText.trim();
      if (text.isEmpty) {
        if (mounted) {
          setState(() {
            _message =
                'Koi Arabic speech recognize nahi hui. Mic permission aur internet check karke dobara parhein.';
          });
        }
        return;
      }

      if (mounted) setState(() => _spokenText = text);
      await _evaluateCurrentAyah();
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _message =
              'AI analysis mein zyada waqt lag raha hai. Dobara chhoti ayat ke saath try karein.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'Voice analysis mein error: $e');
      }
    } finally {
      _usingOnlineQrc = false;
      _qrcService = null;
      _finishing = false;
    }
  }

  Future<void> _evaluateCurrentAyah() async {
    final ayah = _currentAyah;

    if (ayah == null) {
      return;
    }

    final expectedWords = _splitWords(ayah.arabic);
    final spokenWords = _splitWords(_spokenText);

    final targetIndexes = _retryMode && _retryWordIndexes.isNotEmpty
        ? _retryWordIndexes
        : List<int>.generate(expectedWords.length, (i) => i);
    final targetWords = targetIndexes.map((i) => expectedWords[i]).toList();
    final expectedNormalized = targetWords
        .map(_normalizeArabic)
        .toList(growable: false);
    final spokenNormalized = spokenWords
        .map(_normalizeArabic)
        .toList(growable: false);

    final attemptResults = _alignWords(
      targetWords,
      expectedNormalized,
      spokenNormalized,
      spokenWords,
    );

    final results = _retryMode && _results.length == expectedWords.length
        ? List<_WordResult>.from(_results)
        : expectedWords
            .map((word) => _WordResult(word, _WordStatus.pending))
            .toList();

    for (var i = 0; i < targetIndexes.length; i++) {
      results[targetIndexes[i]] = attemptResults[i];
    }

    final correct = results
        .where((item) => item.status == _WordStatus.correct)
        .length;
    final wrong = results
        .where((item) => item.status != _WordStatus.correct)
        .length;

    // Always persist the current attempt. History is upserted by Surah + Ayah,
    // so repeated checks update the current record instead of creating duplicates.
    // Progress is monotonic: an older ayah can never overwrite newer progress.
    final savedProgress = await StorageService.getQuranProgress(
      widget.selectedSurah.number,
    );
    final accuracy = expectedWords.isEmpty ? 0.0 : correct / expectedWords.length;
    // Only advance the Quran progress when the ayah was substantially
    // recited correctly. A failed attempt remains feedback/history only.
    final completedThrough = accuracy >= 0.80 && ayah.numberInSurah > savedProgress
        ? ayah.numberInSurah
        : savedProgress;

    await StorageService.saveQuranProgress(
      widget.selectedSurah.number,
      completedThrough,
    );

    await StorageService.saveOrUpdateQuranHistory(
      surahNumber: widget.selectedSurah.number,
      surahName: widget.selectedSurah.transliteration,
      ayahNumber: ayah.numberInSurah,
      correctWords: correct,
      wrongWords: wrong,
      wordStatuses: results
          .map((item) => {
                'word': item.word,
                'status': item.status.name,
              })
          .toList(growable: false),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _results = List.unmodifiable(results);
      _isEvaluated = true;
      _retryMode = false;
      _retryWordIndexes = const [];
      _message = wrong == 0
          ? 'MashaAllah! Ayat ke tamam lafz sahi hain.'
          : 'Feedback: $correct sahi, $wrong dobara parhein. Agli dafa sirf red/orange lafz check honge.';
    });
  }

  List<_WordResult> _alignWords(
    List<String> expectedWords,
    List<String> expectedNormalized,
    List<String> spokenNormalized,
    List<String> spokenWords,
  ) {
    final n = expectedNormalized.length;
    final m = spokenNormalized.length;

    if (n == 0) {
      return const [];
    }

    if (m == 0) {
      return expectedWords
          .map((word) => _WordResult(word, _WordStatus.wrong))
          .toList(growable: false);
    }

    const gapExpected = -0.58;
    const gapSpoken = -0.34;
    final dp = List.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, double.negativeInfinity),
    );
    final trace = List.generate(
      n + 1,
      (_) => List<_Trace>.filled(m + 1, _Trace.none),
    );

    dp[0][0] = 0;
    for (var i = 1; i <= n; i++) {
      dp[i][0] = dp[i - 1][0] + gapExpected;
      trace[i][0] = _Trace.skipExpected;
    }
    for (var j = 1; j <= m; j++) {
      dp[0][j] = dp[0][j - 1] + gapSpoken;
      trace[0][j] = _Trace.skipSpoken;
    }

    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final similarity = _similarity(
          expectedNormalized[i - 1],
          spokenNormalized[j - 1],
        );

        final match = dp[i - 1][j - 1] +
            (similarity >= 0.55 ? similarity : -0.70);
        final skipExpected = dp[i - 1][j] + gapExpected;
        final skipSpoken = dp[i][j - 1] + gapSpoken;

        var best = match;
        var operation = _Trace.match;

        if (skipExpected > best) {
          best = skipExpected;
          operation = _Trace.skipExpected;
        }
        if (skipSpoken > best) {
          best = skipSpoken;
          operation = _Trace.skipSpoken;
        }

        dp[i][j] = best;
        trace[i][j] = operation;
      }
    }

    final matchedScores = <int, double>{};
    final matchedSpokenIndexes = <int, int>{};
    var i = n;
    var j = m;

    while (i > 0 || j > 0) {
      final operation = trace[i][j];

      if (operation == _Trace.match && i > 0 && j > 0) {
        matchedScores[i - 1] = _similarity(
          expectedNormalized[i - 1],
          spokenNormalized[j - 1],
        );
        matchedSpokenIndexes[i - 1] = j - 1;
        i--;
        j--;
      } else if (operation == _Trace.skipExpected && i > 0) {
        i--;
      } else if (j > 0) {
        j--;
      } else if (i > 0) {
        i--;
      }
    }

    return List.generate(n, (index) {
      final score = matchedScores[index];
      if (score == null) {
        return _WordResult(
          expectedWords[index],
          _WordStatus.wrong,
        );
      }

      var status = score >= 0.78
          ? _WordStatus.correct
          : score >= 0.60
              ? _WordStatus.improve
              : _WordStatus.wrong;

      // Keep the existing robust letter matching, but add a conservative
      // harakat check when the speech recognizer actually returns diacritics.
      // Most phone ASR engines omit Arabic diacritics; in that case we do not
      // invent a red error because the text alone cannot prove a harakat error.
      final spokenIndex = matchedSpokenIndexes[index];
      if (status == _WordStatus.correct &&
          spokenIndex != null &&
          spokenIndex < spokenWords.length &&
          _containsArabicHarakat(spokenWords[spokenIndex])) {
        if (!_sameArabicHarakat(
          expectedWords[index],
          spokenWords[spokenIndex],
        )) {
          status = _WordStatus.wrong;
        }
      }

      return _WordResult(expectedWords[index], status);
    });
  }

  // Arabic tashkeel/recitation marks. These are deliberately checked
  // separately from _normalizeArabic(), because the latter removes marks
  // for tolerant letter-level matching.
  static final RegExp _arabicHarakatRegExp =
      RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]');

  bool _containsArabicHarakat(String value) {
    return _arabicHarakatRegExp.hasMatch(value);
  }

  List<String> _arabicHarakat(String value) {
    return _arabicHarakatRegExp
        .allMatches(value)
        .map((match) => match.group(0)!)
        .toList(growable: false);
  }

  bool _sameArabicHarakat(String expected, String spoken) {
    final expectedMarks = _arabicHarakat(expected);
    final spokenMarks = _arabicHarakat(spoken);

    // If the recognizer supplies marks, compare them exactly. If it supplies
    // no marks, this function is never called, avoiding false negatives.
    if (expectedMarks.isEmpty || spokenMarks.isEmpty) {
      return true;
    }

    if (expectedMarks.length != spokenMarks.length) {
      return false;
    }

    for (var i = 0; i < expectedMarks.length; i++) {
      if (expectedMarks[i] != spokenMarks[i]) {
        return false;
      }
    }

    return true;
  }

  List<String> _splitWords(String text) {
    return text
        .replaceAll(RegExp(r'[۞۝]'), ' ')
        .split(RegExp(r'\s+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  String _normalizeArabic(String value) {
    return value
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
        .replaceAll('ـ', '')
        .replaceAll('ٱ', 'ا')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ى', 'ي')
        .replaceAll('ۀ', 'ه')
        .replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
  }

  double _similarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1;
    if (a.isEmpty || b.isEmpty) return 0;

    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = [
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }

    final distance = previous[b.length];
    final maxLength = a.length > b.length ? a.length : b.length;
    return maxLength == 0 ? 1 : 1 - (distance / maxLength);
  }

  void _reset() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
      _isEvaluated = false;
      _spokenText = '';
      _results = const [];
      _retryMode = false;
      _retryWordIndexes = const [];
      _message =
          'Mic dabayein aur poori ayat parhein.';
    });
  }

  Future<void> _changeAyah(
    int delta,
  ) async {
    if (_isListening) {
      if (_usingOnlineQrc) {
        await _qrcService?.stop();
      }
      _isListening = false;
      _usingOnlineQrc = false;
      _qrcService = null;
    }

    await QuranAudioService.stop();

    final next =
        _currentAyahIndex + delta;

    if (next < 0 ||
        next >= _ayahs.length) {
      return;
    }

    setState(() {
      _currentAyahIndex = next;

      _isListening = false;
      _isEvaluated = false;

      _spokenText = '';
      _results = const [];

      _message =
          'Mic dabayein aur poori ayat parhein.';

      _audioPlaying = false;
      _audioDownloaded = false;
    });

    await _refreshAudioState();
    await _restoreSavedAyahFeedback();

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF18352C),
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4EE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: primaryGreen,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.selectedSurah.transliteration,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  const Text(
                    'Quran Practice',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF718078),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _reset,
            tooltip: 'Reset',
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
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

          final ayah = _currentAyah;
          if (ayah == null) {
            return const Center(child: Text('Ayah available nahi hai.'));
          }

          final progress = widget.selectedSurah.ayahCount == 0
              ? 0.0
              : ((_currentAyahIndex + 1) / widget.selectedSurah.ayahCount)
                  .clamp(0.0, 1.0)
                  .toDouble();

          return Stack(
            children: [
              SafeArea(
                child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth > 1040
                    ? 980.0
                    : constraints.maxWidth;

                return Center(
                  child: SizedBox(
                    width: maxWidth,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFDCE7E2),
                                  ),
                                ),
                                child: Text(
                                  'Ayah ${ayah.numberInSurah} / ${widget.selectedSurah.ayahCount}',
                                  style: const TextStyle(
                                    color: Color(0xFF29443A),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 7,
                                    backgroundColor: const Color(0xFFDDE7E2),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                      primaryGreen,
                                    ),
                                  ),
                                ),
                              ),
                              if (_isEvaluated) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE6F5EC),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.check_circle_rounded,
                                    color: primaryGreen,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: constraints.maxHeight < 680 ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(18, 2, 18, constraints.maxHeight < 680 ? 6 : 24),
                            child: Column(
                              children: [
                                if (_modelPreparing) _buildModelProgressCard(),
                                _buildAiStatusCard(),
                                _buildAyahCard(ayah),
                                const SizedBox(height: 16),
                                _buildPracticeCard(ayah),
                                if (_spokenText.trim().isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  _buildRecognizedSpeechCard(),
                                ],
                                const SizedBox(height: 14),
                                _buildAudioActions(),
                              ],
                            ),
                          ),
                        ),
                        _buildRecitationBar(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
              if (_firstModelDownload) _buildFirstDownloadOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFirstDownloadOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: const Color(0xEE0B1713),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_download_rounded, color: primaryGreen, size: 48),
              const SizedBox(height: 14),
              const Text('Quran Voice AI tayyar ho raha hai', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF17382E))),
              const SizedBox(height: 8),
              const Text('Pehli dafa model download ho raha hai. Is process ke dauran app ke doosre tasks band hain.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF65756E))),
              const SizedBox(height: 18),
              ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: _modelProgress, minHeight: 9, color: primaryGreen, backgroundColor: Color(0xFFE4EEE9))),
              const SizedBox(height: 8),
              Text('${(_modelProgress * 100).round()}%  •  Please wait', style: const TextStyle(fontWeight: FontWeight.w800, color: primaryGreen)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildAiStatusCard() {
    final active = _isListening || _modelPreparing;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active ? const [Color(0xFF0C8C68), Color(0xFF075943)] : const [Color(0xFFEAF7F1), Color(0xFFF7FBF9)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? Colors.transparent : const Color(0xFFDCEBE4)),
      ),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: active ? Colors.white.withOpacity(.16) : Colors.white, borderRadius: BorderRadius.circular(14)), child: Icon(active ? Icons.graphic_eq_rounded : Icons.auto_awesome_rounded, color: active ? Colors.white : primaryGreen)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(active ? 'AI Voice Analysis' : 'Quran Voice Coach', style: TextStyle(color: active ? Colors.white : const Color(0xFF17382E), fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(active ? 'Audio ko ayah ke against analyze kiya ja raha hai' : 'Local Quran voice engine ready for recitation practice', style: TextStyle(color: active ? const Color(0xE6FFFFFF) : const Color(0xFF6D7D76), fontSize: 10.5)),
        ])),
      ]),
    );
  }

  Widget _buildModelProgressCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDCE9E3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Preparing offline Quran voice engine', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF20362E))),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _modelProgress, minHeight: 7, color: primaryGreen, backgroundColor: const Color(0xFFE4EEE9))),
        const SizedBox(height: 6),
        Text('${(_modelProgress * 100).round()}% • First setup only', style: const TextStyle(fontSize: 10.5, color: Color(0xFF73827B))),
      ]),
    );
  }


  Widget _buildAyahCard(AyahModel ayah) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE9E3)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 20,
            offset: Offset(0, 8),
            color: Color(0x10000000),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF6F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'آیت ${ayah.numberInSurah}',
              style: const TextStyle(
                color: primaryGreen,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            ayah.arabic,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _selectedScript == 'Indo-Pak' ? 'IndoPak' : 'UthmanicHafs',
              fontSize: 31,
              height: 2.0,
              fontWeight: FontWeight.w400,
              color: Color(0xFF17231F),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAF8),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFE7EEEA)),
            ),
            child: Text(
              ayah.urduTranslation,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                height: 1.8,
                color: Color(0xFF394940),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeCard(AyahModel ayah) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E8E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF6F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.record_voice_over_rounded,
                  color: primaryGreen,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEvaluated
                          ? 'Word-by-word feedback'
                          : 'Practice words',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF20362E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isEvaluated
                          ? 'Aapki recitation ka feedback'
                          : 'Ayat ko lafz-ba-lafz practice karein',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF78867F),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildArabicWords(ayah),
          if (_selectedWordIndex != null && _selectedWordIndex! < _splitWords(ayah.arabic).length) ...[
            const SizedBox(height: 10),
            Text('Selected word: ${_splitWords(ayah.arabic)[_selectedWordIndex!]} • Tap a word to practice it', textDirection: TextDirection.rtl, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Color(0xFF6D7D76), fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 13),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _legendDot('Correct', Colors.green.shade50, Colors.green.shade800),
              _legendDot('Improve', Colors.orange.shade50, Colors.orange.shade900),
              _legendDot('Wrong', Colors.red.shade50, Colors.red.shade800),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: const Color(0xFFF4F8F6), borderRadius: BorderRadius.circular(14)),
            child: const Row(children: [
              Icon(Icons.school_rounded, size: 18, color: primaryGreen),
              SizedBox(width: 8),
              Expanded(child: Text('Tajweed focus: lafz ko ahista parhein; ghunnah, madd, qalqalah aur makhraj par tawajjoh dein. Text matching harakat ko preserve karta hai, lekin complete acoustic Tajweed grading abhi separate learning guidance hai.', style: TextStyle(fontSize: 10.5, height: 1.45, color: Color(0xFF5F7068)))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _audioBusy
                ? null
                : (_audioPlaying ? _stopAudio : _playAudio),
            icon: Icon(
              _audioPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
              size: 19,
            ),
            label: Text(_audioPlaying ? 'Stop' : 'Listen'),
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryGreen,
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFD6E4DE)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _audioBusy || _audioDownloaded
                ? null
                : _downloadCurrentAudio,
            icon: Icon(
              _audioDownloaded
                  ? Icons.download_done_rounded
                  : Icons.download_for_offline_rounded,
              size: 19,
            ),
            label: Text(_audioDownloaded ? 'Saved offline' : 'Save offline'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _audioDownloaded
                  ? const Color(0xFF5E7068)
                  : const Color(0xFF29443A),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFD6E4DE)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecognizedSpeechCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCF7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAE4D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hearing_rounded, size: 17, color: Color(0xFF7B6B42)),
              SizedBox(width: 7),
              Text(
                'Recognized speech',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF5F5438),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            _spokenText,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: _selectedScript == 'Indo-Pak' ? 'IndoPak' : 'UthmanicHafs',
              fontSize: 20,
              height: 1.7,
              color: Color(0xFF302C22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecitationBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 13),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, -5),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Text(
              _message,
              key: ValueKey(_message),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: _isListening
                    ? Colors.red.shade700
                    : const Color(0xFF4E6B5F),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _toggleListening,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _isListening ? 66 : 60,
              height: _isListening ? 66 : 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening
                    ? Colors.red.shade600
                    : primaryGreen,
                boxShadow: [
                  BoxShadow(
                    color: (_isListening
                            ? Colors.red.shade600
                            : primaryGreen)
                        .withOpacity(0.22),
                    blurRadius: 16,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 29,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _isListening ? 'Listening… tap to stop' : 'Tap to recite',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64746D),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _currentAyahIndex > 0
                      ? () => _changeAyah(-1)
                      : null,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Previous'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(43),
                    foregroundColor: const Color(0xFF365047),
                    side: const BorderSide(color: Color(0xFFD7E2DD)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _currentAyahIndex < _ayahs.length - 1
                      ? () => _changeAyah(1)
                      : null,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Next'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(43),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildArabicWords(AyahModel ayah) {
    final words = _splitWords(ayah.arabic);
    final displayWords = _results.length == words.length
        ? _results
        : words
            .map((word) => _WordResult(word, _WordStatus.pending))
            .toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        textDirection: TextDirection.rtl,
        spacing: 7,
        runSpacing: 9,
        children: displayWords.map((item) {
          final colors = switch (item.status) {
            _WordStatus.correct => (Colors.green.shade50, Colors.green.shade800),
            _WordStatus.improve => (Colors.orange.shade50, Colors.orange.shade900),
            _WordStatus.wrong => (Colors.red.shade50, Colors.red.shade800),
            _WordStatus.pending => (Colors.white, Colors.black87),
          };

          final wordIndex = displayWords.indexOf(item);
          return InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () {
              setState(() => _selectedWordIndex = wordIndex);
              if (_isEvaluated && item.status != _WordStatus.correct) {
                setState(() => _message = 'Is lafz ko dobara ahista aur Tajweed ke sath parhein.');
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: colors.$1,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: colors.$2.withOpacity(0.18), width: _selectedWordIndex == wordIndex ? 2 : 1),
              ),
              child: Text(
                item.word,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: _selectedScript == 'Indo-Pak' ? 'IndoPak' : 'UthmanicHafs',
                  fontSize: 24,
                  height: 1.55,
                  color: colors.$2,
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

enum _WordStatus { pending, correct, improve, wrong }
enum _Trace { none, match, skipExpected, skipSpoken }

class _WordResult {
  final String word;
  final _WordStatus status;

  const _WordResult(this.word, this.status);
}

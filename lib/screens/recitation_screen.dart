import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/ayah_model.dart';
import '../models/surah_model.dart';
import '../services/quran_service.dart';
import '../services/quran_audio_service.dart';
import '../services/storage_service.dart';
import '../services/offline_asr_service.dart';

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

  late final stt.SpeechToText _speech;
  late final Future<void> _quranFuture;

  List<AyahModel> _ayahs = const [];

  int _currentAyahIndex = 0;

  bool _isListening = false;
  bool _isEvaluated = false;
  bool _finishing = false;

  bool _audioBusy = false;
  bool _audioDownloaded = false;
  bool _audioPlaying = false;
  bool _usingOfflineAsr = false;
  bool _modelPreparing = false;
  double _modelProgress = 0;
  bool _usingOnlineSpeech = false;
  bool _acceptingSpeechResults = false;
  bool _firstDownloadBlocking = false;
  String _onlineSpeechText = '';

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

    _speech = stt.SpeechToText();

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

    await _restoreSavedAyahResult();
    await _refreshAudioState();
  }

  @override
  void dispose() {
    _speech.stop();
    OfflineAsrService.dispose();
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

  Future<void> _restoreSavedAyahResult() async {
    final ayah = _currentAyah;
    if (ayah == null) return;

    final saved = await StorageService.getQuranHistoryForAyah(
      surahNumber: widget.selectedSurah.number,
      ayahNumber: ayah.numberInSurah,
    );
    if (!mounted || saved == null) return;

    final raw = saved['wordStatuses'];
    final restored = raw is List
        ? raw.whereType<Map>().map((item) {
            final map = Map<String, dynamic>.from(item);
            final status = _WordStatus.values.firstWhere(
              (value) => value.name == map['status']?.toString(),
              orElse: () => _WordStatus.wrong,
            );
            return _WordResult(map['word']?.toString() ?? '', status);
          }).where((item) => item.word.isNotEmpty).toList()
        : <_WordResult>[];

    if (restored.isEmpty) return;
    setState(() {
      _results = List.unmodifiable(restored);
      _isEvaluated = true;
      _message = 'Is ayat ki pichli checking aur word colors restore ho gaye.';
    });
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

  Future<String?> _bestArabicLocale() async {
    try {
      final locales = await _speech.locales();
      const preferred = <String>['ar-SA', 'ar-AE', 'ar-EG', 'ar'];
      for (final wanted in preferred) {
        for (final locale in locales) {
          if (locale.localeId.toLowerCase() == wanted.toLowerCase()) {
            return locale.localeId;
          }
        }
      }
      final arabic = locales.where(
        (locale) => locale.localeId.toLowerCase().startsWith('ar'),
      );
      if (arabic.isNotEmpty) return arabic.first.localeId;
    } catch (_) {}
    return null;
  }

  Future<bool> _startOnlineSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') &&
            _isListening &&
            _usingOnlineSpeech &&
            !_finishing) {
          _finishListening();
        }
      },
      onError: (error) {
        if (!mounted) return;
        if (_isListening && _usingOnlineSpeech) {
          setState(() {
            _message = 'Online voice recognition ruk gayi. Dobara parhein.';
          });
        }
      },
    );

    if (!available) return false;

    final localeId = await _bestArabicLocale();
    if (localeId == null) return false;

    _usingOnlineSpeech = true;
    _acceptingSpeechResults = true;
    _onlineSpeechText = '';
    _spokenText = '';

    await _speech.listen(
      localeId: localeId,
      partialResults: true,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      cancelOnError: false,
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _onlineSpeechText = result.recognizedWords.trim();
          _spokenText = _onlineSpeechText;
        });
      },
    );

    return true;
  }

  Future<void> _startListening() async {
    final ayah = _currentAyah;
    if (ayah == null || _isListening || _finishing) return;

    await QuranAudioService.stop();
    if (mounted) setState(() => _audioPlaying = false);

    _sessionToken = DateTime.now().microsecondsSinceEpoch;
    _savedSessionToken = null;
    _usingOfflineAsr = false;
    _usingOnlineSpeech = false;
    _acceptingSpeechResults = false;
    _onlineSpeechText = '';
    _spokenText = '';

    // After an ayah has been checked, retry only the words that were not
    // correct. This avoids forcing the user to repeat the whole ayah.
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

    // Prefer the phone's online speech recognizer first. This gives immediate
    // feedback after recording and does not require a 150 MB model download.
    try {
      final onlineStarted = await _startOnlineSpeech();
      if (onlineStarted) {
        if (!mounted) return;
        setState(() {
          _isListening = true;
          _isEvaluated = false;
          _results = const [];
          _message = _retryMode
              ? 'Dobara sirf red/orange lafz parhein: $targetWords'
              : 'Online AI Listening... poori ayat mukammal parhein.';
        });
        return;
      }
    } catch (_) {
      _usingOnlineSpeech = false;
    }

    // If the phone has no online speech service, use the Quran-optimized
    // offline Whisper model as the fallback.
    if (!kIsWeb) {
      try {
        var ready = await OfflineAsrService.isModelReady();
        if (!ready) {
          if (mounted) {
            setState(() {
              _modelPreparing = true;
              _modelProgress = 0;
              _message = 'Offline Quran AI prepare ho raha hai...';
            });
          }
          await OfflineAsrService.downloadModel(onProgress: (value) {
            if (mounted) {
              setState(() => _modelProgress = value.clamp(0.0, 1.0));
            }
          });
          ready = await OfflineAsrService.isModelReady();
        }
        if (!ready) throw StateError('AI voice model is not ready.');
        if (mounted) {
          setState(() {
            _firstDownloadBlocking = false;
            _modelPreparing = false;
            _message = 'Quran Voice AI ready hai. Ab recitation shuru karein.';
          });
        }

        await OfflineAsrService.startRecording();
        if (!mounted) return;
        setState(() {
          _usingOfflineAsr = true;
          _modelPreparing = false;
          _isListening = true;
          _isEvaluated = false;
          _spokenText = '';
          _results = const [];
          _message = _retryMode
              ? 'Dobara sirf red/orange lafz parhein: $targetWords'
              : 'Offline AI Listening... poori ayat mukammal parhein.';
        });
        return;
      } catch (e) {
        if (mounted) {
          setState(() {
            _firstDownloadBlocking = false;
            _modelPreparing = false;
            _message = 'Voice recognition start nahi hui: $e';
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _isListening = false;
        _message = 'Arabic speech recognition is device par available nahi hai.';
      });
    }
  }

  Future<void> _finishListening() async {
    if (!_isListening || _finishing) return;
    _finishing = true;
    if (mounted) {
      setState(() {
        _isListening = false;
        _message = 'Recitation complete — text analysis ho rahi hai...';
      });
    }

    try {
      if (_usingOnlineSpeech) {
        await _speech.stop();
        _acceptingSpeechResults = false;
        _spokenText = _onlineSpeechText.trim();
      } else if (_usingOfflineAsr) {
        _acceptingSpeechResults = false;
        final recognized = await OfflineAsrService.stopAndRecognize()
            .timeout(const Duration(seconds: 45));
        _spokenText = recognized.trim();
      } else {
        await _speech.stop();
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
      _acceptingSpeechResults = false;
      _usingOnlineSpeech = false;
      _usingOfflineAsr = false;
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
    // Ignore tashkeel/waqf marks for tolerant letter matching. The marks are
    // checked separately when the speech engine actually returns them.
    return value
        .replaceAll(_arabicHarakatRegExp, '')
        .replaceAll(RegExp(r'[\u0610-\u061A]'), '')
        .replaceAll('ـ', '')
        .replaceAll('ٱ', 'ا')
        .replaceAll(RegExp(r'[أإآٲٳٵٶ]'), 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ء', '')
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

    _acceptingSpeechResults = false;
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
      if (_usingOfflineAsr) {
        await OfflineAsrService.cancelRecording();
        _usingOfflineAsr = false;
      } else {
        await _speech.stop();
      }
    }

    await QuranAudioService.stop();

    final next =
        _currentAyahIndex + delta;

    if (next < 0 ||
        next >= _ayahs.length) {
      return;
    }

    _acceptingSpeechResults = false;
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

    await _restoreSavedAyahResult();
    await _refreshAudioState();
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
      body: Stack(
        children: [
          FutureBuilder<void>(
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

          return SafeArea(
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
                            padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
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
          );
        },
      ),
          if (_firstDownloadBlocking)
            Positioned.fill(
              child: Material(
                color: Colors.black.withOpacity(0.58),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(28),
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.download_for_offline_rounded,
                          color: primaryGreen,
                          size: 46,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Pehli dafa Quran Voice AI download ho raha hai',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF18352C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please wait. Download complete hone tak koi aur task nahi chalega.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF65736D),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        LinearProgressIndicator(
                          value: _modelProgress > 0 ? _modelProgress : null,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                          color: primaryGreen,
                          backgroundColor: const Color(0xFFE3ECE8),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          '${(_modelProgress * 100).round()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
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

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: colors.$1,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: colors.$2.withOpacity(0.18)),
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

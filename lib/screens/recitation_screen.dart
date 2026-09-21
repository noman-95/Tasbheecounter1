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

  String _spokenText = '';
  String _message = 'Mic dabayein aur poori ayat parhein.';
  String _selectedScript = 'Uthmani';

  List<_WordResult> _results = const [];

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

  Future<void> _startListening() async {
    final ayah = _currentAyah;
    if (ayah == null || _isListening || _finishing) return;

    await QuranAudioService.stop();
    if (mounted) setState(() => _audioPlaying = false);

    _sessionToken = DateTime.now().microsecondsSinceEpoch;
    _savedSessionToken = null;

    // Android/iOS: prefer the local Quran Whisper/Sherpa engine.
    // Web/desktop keeps speech_to_text as a development fallback.
    if (!kIsWeb) {
      try {
        var ready = await OfflineAsrService.isModelReady();
        if (!ready) {
          if (mounted) {
            setState(() {
              _modelPreparing = true;
              _modelProgress = 0;
              _message = 'AI Quran voice engine prepare ho raha hai...';
            });
          }
          await OfflineAsrService.downloadModel(onProgress: (value) {
            if (mounted) setState(() => _modelProgress = value.clamp(0.0, 1.0));
          });
          ready = await OfflineAsrService.isModelReady();
        }
        if (!ready) throw StateError('AI voice model is not ready.');

        await OfflineAsrService.startRecording();
        if (!mounted) return;
        setState(() {
          _usingOfflineAsr = true;
          _modelPreparing = false;
          _isListening = true;
          _isEvaluated = false;
          _spokenText = '';
          _results = const [];
          _message = 'AI Listening... poori ayat mukammal parhein.';
        });
        return;
      } catch (e) {
        if (mounted) {
          setState(() {
            _modelPreparing = false;
            _message = 'AI voice engine start nahi hua. Fallback recognition use ho rahi hai.';
          });
        }
      }
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && _isListening && !_finishing) {
          _finishListening();
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          _message = 'Mic mein error aaya. Dobara try karein.';
        });
      },
    );

    if (!available) {
      if (mounted) setState(() => _message = 'Microphone/speech recognition available nahi hai.');
      return;
    }

    setState(() {
      _usingOfflineAsr = false;
      _isListening = true;
      _isEvaluated = false;
      _spokenText = '';
      _results = const [];
      _message = 'Listening... poori ayat mukammal parhein.';
    });

    await _speech.listen(
      localeId: 'ar_SA',
      partialResults: true,
      onResult: (result) {
        if (!mounted) return;
        setState(() => _spokenText = result.recognizedWords);
      },
    );
  }

  Future<void> _finishListening() async {
    if (!_isListening || _finishing) return;
    _finishing = true;
    if (mounted) {
      setState(() {
        _isListening = false;
        _message = 'Recitation complete — audio analysis ho rahi hai...';
      });
    }

    try {
      if (_usingOfflineAsr) {
        final recognized = await OfflineAsrService.stopAndRecognize();
        if (mounted) setState(() => _spokenText = recognized.trim());
      } else {
        await _speech.stop();
      }

      if (_spokenText.trim().isEmpty) {
        if (mounted) setState(() => _message = 'Koi speech recognize nahi hui. Dobara poori ayat parhein.');
        return;
      }

      await _evaluateCurrentAyah();
    } catch (e) {
      if (mounted) setState(() => _message = 'Voice analysis mein error: $e');
    } finally {
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
    final expectedNormalized = expectedWords
        .map(_normalizeArabic)
        .toList(growable: false);
    final spokenNormalized = spokenWords
        .map(_normalizeArabic)
        .toList(growable: false);

    final results = _alignWords(
      expectedWords,
      expectedNormalized,
      spokenNormalized,
    );

    final correct = results
        .where((item) => item.status == _WordStatus.correct)
        .length;
    final wrong = results.length - correct;

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
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _results = List.unmodifiable(results);
      _isEvaluated = true;
      _message =
          'Feedback: $correct sahi, $wrong mein improvement chahiye.';
    });
  }

  List<_WordResult> _alignWords(
    List<String> expectedWords,
    List<String> expectedNormalized,
    List<String> spokenNormalized,
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
    var i = n;
    var j = m;

    while (i > 0 || j > 0) {
      final operation = trace[i][j];

      if (operation == _Trace.match && i > 0 && j > 0) {
        matchedScores[i - 1] = _similarity(
          expectedNormalized[i - 1],
          spokenNormalized[j - 1],
        );
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

      final status = score >= 0.78
          ? _WordStatus.correct
          : score >= 0.60
              ? _WordStatus.improve
              : _WordStatus.wrong;

      return _WordResult(expectedWords[index], status);
    });
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
        .replaceAll('ة', 'ه')
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

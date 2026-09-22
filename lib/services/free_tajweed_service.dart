import 'dart:async';
import 'dart:typed_data';

import 'package:recite_quran/recite_quran.dart';

/// Final on-device recitation/Tajweed bridge.
///
/// Uses recite_quran's streaming Zipformer + DTW + deterministic Tajweed
/// checks. The package is intentionally free/no-ads/no-subscription and
/// follows the Quran-Lab NPL terms.
class FreeTajweedService {
  static QuranRepository? _repository;
  static ReciteQuran? _tracker;
  static AudioProcessor? _audio;
  static StreamSubscription<WordMatchedEvent>? _wordSub;
  static StreamSubscription<String>? _textSub;
  static bool _ready = false;
  static Future<void>? _initializing;
  static bool _running = false;
  static int _globalStart = 0;
  static int _ayahWordCount = 0;
  static void Function(FreeTajweedWordEvent event)? _onWord;
  static void Function(String text)? _onTranscript;

  static Future<bool> isModelReady() async {
    // recite_quran owns model extraction/loading. initialize() is the real
    // readiness check, so this stays true and lets the package report a
    // missing model with a useful error to the UI.
    return true;
  }

  static Future<void> initialize() async {
    if (_ready) return;
    final existing = _initializing;
    if (existing != null) {
      await existing;
      return;
    }

    final future = () async {
      final metadata = QuranMetadataService();
      _repository = QuranRepository(metadata);
      await _repository!.loadSurahAsync(1);
      _tracker = ReciteQuran(
        repository: _repository!,
        config: TrackerConfig.normal(),
        isTajweed: true,
      );
      await _tracker!.initialize();
      _ready = true;
    }();

    _initializing = future;
    try {
      await future;
    } finally {
      if (identical(_initializing, future)) {
        _initializing = null;
      }
    }
  }

  static Future<void> start({
    required int surah,
    required int ayah,
    required int ayahWordCount,
    required int globalWordOffset,
    required void Function(FreeTajweedWordEvent event) onWord,
    void Function(String text)? onTranscript,
    int? startWordInAyah,
  }) async {
    await initialize();
    _ayahWordCount = ayahWordCount;
    final base = globalWordOffset;
    _globalStart = base + (startWordInAyah ?? 0);
    _onWord = onWord;
    _onTranscript = onTranscript;

    await _wordSub?.cancel();
    await _textSub?.cancel();
    _tracker!.resetBuffer();
    _tracker!.setTajweedMode(true);
    _tracker!.setTargetSurah(surah, startGlobalWord: _globalStart, forceClear: false);

    _wordSub = _tracker!.onWordMatched.listen((event) {
      final local = event.wordId - base;
      if (local < 0 || local >= _ayahWordCount) return;
      final tajweed = event.tajweedErrors ?? const <Map<String, dynamic>>[];
      final status = event.isRed
          ? FreeTajweedWordStatus.wrong
          : tajweed.isNotEmpty
              ? FreeTajweedWordStatus.improve
              : FreeTajweedWordStatus.correct;
      _onWord?.call(FreeTajweedWordEvent(
        wordIndex: local,
        status: status,
        score: event.score,
        tajweedErrors: tajweed,
      ));
    });

    _textSub = _tracker!.onTranscript.listen((text) {
      if (text.trim().isNotEmpty) _onTranscript?.call(text.trim());
    });

    _audio = AudioProcessor();
    _running = true;
    await _audio!.start(
      onChunk: (Float32List chunk, bool isFinal) {
        if (!_running) return;
        _tracker?.feedAudioChunk(chunk, isFinal: isFinal);
      },
    );
  }

  static Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _audio?.stop();
    } finally {
      _audio = null;
      _tracker?.resetBuffer();
    }
  }

  static Future<void> dispose() async {
    _running = false;
    await _audio?.stop();
    _audio = null;
    await _wordSub?.cancel();
    await _textSub?.cancel();
    _wordSub = null;
    _textSub = null;
    _tracker?.dispose();
    _tracker = null;
    _initializing = null;
    _repository = null;
    _ready = false;
    _onWord = null;
    _onTranscript = null;
  }
}

enum FreeTajweedWordStatus { correct, improve, wrong }

class FreeTajweedWordEvent {
  final int wordIndex;
  final FreeTajweedWordStatus status;
  final double score;
  final List<Map<String, dynamic>> tajweedErrors;

  const FreeTajweedWordEvent({
    required this.wordIndex,
    required this.status,
    required this.score,
    required this.tajweedErrors,
  });
}

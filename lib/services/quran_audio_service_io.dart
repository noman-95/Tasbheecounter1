import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ayah_model.dart';

/// Quran audio cache.
///
/// The first play/download needs internet. After an ayah is cached locally,
/// that ayah can be played without internet.
class QuranAudioService {
  static final AudioPlayer _player = AudioPlayer();

  static String _url(int surahNumber, int ayahNumber) {
    // Mishary Rashid Al Afasy, public per-ayah audio source.
    return 'https://the-quran-project.github.io/Quran-Audio/Data/1/'
        '${surahNumber}_$ayahNumber.mp3';
  }

  static Future<Directory> _audioDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}quran_audio');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _file(int surahNumber, int ayahNumber) async {
    final dir = await _audioDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}${surahNumber}_$ayahNumber.mp3',
    );
  }

  static Future<bool> isDownloaded(AyahModel ayah, int surahNumber) async {
    return (await _file(surahNumber, ayah.numberInSurah)).exists();
  }

  static Future<void> download(AyahModel ayah, int surahNumber) async {
    final file = await _file(surahNumber, ayah.numberInSurah);
    if (await file.exists() && await file.length() > 1024) return;

    final client = HttpClient();
    final temp = File('${file.path}.part');
    try {
      final request = await client.getUrl(
        Uri.parse(_url(surahNumber, ayah.numberInSurah)),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Audio download failed (HTTP ${response.statusCode})',
          uri: Uri.parse(_url(surahNumber, ayah.numberInSurah)),
        );
      }

      final sink = temp.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }
      await temp.rename(file.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> play(AyahModel ayah, int surahNumber) async {
    final file = await _file(surahNumber, ayah.numberInSurah);
    if (!await file.exists()) {
      await download(ayah, surahNumber);
    }
    await _player.setFilePath(file.path);
    unawaited(_player.play());
  }

  static Future<void> stop() => _player.stop();

  static bool get isPlaying => _player.playing;

  static Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  static Future<void> downloadSurah(
    List<AyahModel> ayahs,
    int surahNumber, {
    void Function(int done, int total)? onProgress,
  }) async {
    final total = ayahs.length;
    for (var i = 0; i < ayahs.length; i++) {
      await download(ayahs[i], surahNumber);
      onProgress?.call(i + 1, total);
    }
  }
}

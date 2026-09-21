import 'package:just_audio/just_audio.dart';

import '../models/ayah_model.dart';

class QuranAudioService {
  static final AudioPlayer _player = AudioPlayer();

  static String _url(int surahNumber, int ayahNumber) =>
      'https://the-quran-project.github.io/Quran-Audio/Data/1/'
      '${surahNumber}_$ayahNumber.mp3';

  static Future<bool> isDownloaded(AyahModel ayah, int surahNumber) async => false;

  static Future<void> play(AyahModel ayah, int surahNumber) async {
    await _player.setUrl(_url(surahNumber, ayah.numberInSurah));
    _player.play();
  }

  static Future<void> download(AyahModel ayah, int surahNumber) async {
    throw UnsupportedError(
      'Offline audio download is not available on Web. Use Android/iOS for offline audio.',
    );
  }

  static Future<void> downloadSurah(
    List<AyahModel> ayahs,
    int surahNumber, {
    void Function(int done, int total)? onProgress,
  }) async {
    throw UnsupportedError(
      'Offline audio download is not available on Web. Use Android/iOS for offline audio.',
    );
  }

  static Future<void> stop() => _player.stop();
  static bool get isPlaying => _player.playing;
  static Stream<PlayerState> get playerStateStream => _player.playerStateStream;
}

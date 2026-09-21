class OfflineAsrService {
  static Future<bool> isModelReady() async => false;

  static Future<void> downloadModel({
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError(
      'Offline Quran voice recognition is available on Android/iOS only.',
    );
  }

  static Future<void> startRecording() async {
    throw UnsupportedError(
      'Offline Quran voice recognition is available on Android/iOS only.',
    );
  }

  static Future<String> stopAndRecognize() async {
    throw UnsupportedError(
      'Offline Quran voice recognition is available on Android/iOS only.',
    );
  }

  static Future<void> cancelRecording() async {}

  static Future<void> dispose() async {}
}

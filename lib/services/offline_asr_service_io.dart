import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

/// Local Quran ASR service.
///
/// The model is downloaded once to the application's private storage and
/// then used fully offline for recognition.
class OfflineAsrService {
  static const String _modelUrl =
      'https://github.com/MUmarJ/sherpa-onnx-models/releases/download/'
      'v1.2.0-tarteel/whisper-base-ar-quran-sherpa.zip';

  static const String _modelVersion = 'tarteel-whisper-base-v1';

  static AudioRecorder? _recorder;
  static OfflineRecognizer? _recognizer;
  static String? _recordingPath;
  static Future<void>? _initializing;

  static Future<Directory> _rootDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}/offline_quran_voice');
    if (!root.existsSync()) {
      await root.create(recursive: true);
    }
    return root;
  }

  static Future<File> _modelMarker() async {
    final root = await _rootDirectory();
    return File('${root.path}/model.version');
  }

  static Future<Directory> _modelDirectory() async {
    final root = await _rootDirectory();
    return Directory('${root.path}/model');
  }

  static Future<bool> isModelReady() async {
    final marker = await _modelMarker();
    final modelDir = await _modelDirectory();

    if (!marker.existsSync() || !modelDir.existsSync()) {
      return false;
    }

    final version = (await marker.readAsString()).trim();
    if (version != _modelVersion) return false;

    final requiredFiles = <String>[
      'base-encoder.int8.onnx',
      'base-decoder.int8.onnx',
      'base-tokens.txt',
    ];

    for (final name in requiredFiles) {
      final match = await _findFile(modelDir, name);
      if (match == null || !match.existsSync()) return false;
    }

    return true;
  }

  static Future<File?> _findFile(
    Directory directory,
    String fileName,
  ) async {
    if (!directory.existsSync()) return null;

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.uri.pathSegments.last == fileName) {
        return entity;
      }
    }

    return null;
  }

  static Future<void> downloadModel({
    void Function(double progress)? onProgress,
  }) async {
    if (await isModelReady()) return;

    final root = await _rootDirectory();
    final zipFile = File('${root.path}/model_download.zip');
    final tempDir = Directory('${root.path}/model_tmp');

    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);

    if (zipFile.existsSync()) {
      await zipFile.delete();
    }

    final client = http.Client();

    try {
      final request = http.Request('GET', Uri.parse(_modelUrl));
      final response = await client.send(request).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException('Quran AI model download timed out.'),
      );

      if (response.statusCode != 200) {
        throw HttpException(
          'Model download failed (${response.statusCode}).',
        );
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = zipFile.openWrite();

      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);

          if (total > 0) {
            onProgress?.call(received / total);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      // Archive 4.x can extract ZIPs directly from disk, avoiding a giant
      // in-memory Uint8List for the ~150 MB model package.
      extractFileToDisk(zipFile.path, tempDir.path);

      final encoder = await _findFile(
        tempDir,
        'base-encoder.int8.onnx',
      );
      final decoder = await _findFile(
        tempDir,
        'base-decoder.int8.onnx',
      );
      final tokens = await _findFile(
        tempDir,
        'base-tokens.txt',
      );

      if (encoder == null || decoder == null || tokens == null) {
        throw StateError(
          'Downloaded Quran voice model is incomplete.',
        );
      }

      final modelDir = await _modelDirectory();
      if (modelDir.existsSync()) {
        await modelDir.delete(recursive: true);
      }
      await modelDir.create(recursive: true);

      await encoder.copy('${modelDir.path}/base-encoder.int8.onnx');
      await decoder.copy('${modelDir.path}/base-decoder.int8.onnx');
      await tokens.copy('${modelDir.path}/base-tokens.txt');

      final marker = await _modelMarker();
      await marker.writeAsString(_modelVersion, flush: true);

      onProgress?.call(1.0);
    } finally {
      client.close();

      if (zipFile.existsSync()) {
        await zipFile.delete();
      }

      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  static Future<void> _ensureInitialized() async {
    if (_recognizer != null) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }

    _initializing = _initializeRecognizer();

    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  static Future<void> _initializeRecognizer() async {
    if (!await isModelReady()) {
      throw StateError(
        'Offline Quran voice model is not downloaded yet.',
      );
    }

    initBindings();

    final modelDir = await _modelDirectory();

    final config = OfflineRecognizerConfig(
      model: OfflineModelConfig(
        whisper: OfflineWhisperModelConfig(
          encoder: '${modelDir.path}/base-encoder.int8.onnx',
          decoder: '${modelDir.path}/base-decoder.int8.onnx',
          language: 'ar',
          task: 'transcribe',
          enableTokenTimestamps: true,
        ),
        tokens: '${modelDir.path}/base-tokens.txt',
        modelType: 'whisper',
        numThreads: 2,
        provider: 'cpu',
      ),
      decodingMethod: 'greedy_search',
    );

    _recognizer = OfflineRecognizer(config);
  }

  static Future<void> startRecording() async {
    if (await isModelReady() == false) {
      throw StateError(
        'OFFLINE_MODEL_NOT_READY',
      );
    }

    final recorder = _recorder ??= AudioRecorder();

    final allowed = await recorder.hasPermission();
    if (!allowed) {
      throw StateError(
        'Microphone permission was not granted.',
      );
    }

    final root = await _rootDirectory();
    final audioDir = Directory('${root.path}/recordings');
    if (!audioDir.existsSync()) {
      await audioDir.create(recursive: true);
    }

    final fileName =
        'rec_${DateTime.now().microsecondsSinceEpoch}.wav';
    _recordingPath = '${audioDir.path}/$fileName';

    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
      path: _recordingPath!,
    );
  }

  static Future<String> stopAndRecognize() async {
    final recorder = _recorder;
    if (recorder == null) {
      throw StateError('Recorder is not initialized.');
    }

    final path = await recorder.stop();
    final finalPath = path ?? _recordingPath;
    _recordingPath = null;

    if (finalPath == null || finalPath.isEmpty) {
      throw StateError('No recording file was created.');
    }

    try {
      await _ensureInitialized();

      final wave = readWave(finalPath);

      // Give Whisper a little trailing silence so the final word is not cut
      // off on tightly stopped recordings.
      const silenceSamples = 8000; // 0.5 s at 16 kHz.
      final padded = Float32List(
        wave.samples.length + silenceSamples,
      );
      padded.setAll(0, wave.samples);

      final stream = _recognizer!.createStream();
      try {
        stream.acceptWaveform(
          samples: padded,
          sampleRate: wave.sampleRate,
        );

        _recognizer!.decode(stream);

        return _recognizer!.getResult(stream).text.trim();
      } finally {
        stream.free();
      }
    } finally {
      final recordedFile = File(finalPath);
      if (recordedFile.existsSync()) {
        await recordedFile.delete();
      }
    }
  }

  static Future<void> cancelRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;

    try {
      await recorder.cancel();
    } finally {
      final path = _recordingPath;
      _recordingPath = null;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
        }
      }
    }
  }

  static Future<void> dispose() async {
    await cancelRecording();
    _recognizer?.free();
    _recognizer = null;
    _recorder?.dispose();
    _recorder = null;
  }
}

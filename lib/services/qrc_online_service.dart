import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';

/// Self-hosted Sanad Tajweed client.
///
/// The mobile app does NOT contain a paid API key. It records one ayah as
/// 16-kHz mono PCM and sends a WAV to the user's own Sanad server on stop.
/// The server returns word_scores + measured Tajweed rule results.
class QrcOnlineService {
  static const String _baseUrl = String.fromEnvironment(
    'SANAD_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  final List<int> _pcm = <int>[];
  final StreamController<Map<String, dynamic>> _results =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _started = false;
  bool _stopping = false;
  int _chapter = 0;
  int _verse = 0;

  bool get configured => _baseUrl.trim().isNotEmpty;
  Stream<Map<String, dynamic>> get results => _results.stream;

  Future<bool> start({
    required int chapterIndex,
    required int verseIndex,
    int wordIndex = 1,
    int hafzLevel = 1,
    int tajweedLevel = 3,
  }) async {
    if (_started || _stopping || !configured) return false;

    try {
      final recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        await recorder.dispose();
        return false;
      }

      _recorder = recorder;
      _chapter = chapterIndex;
      _verse = verseIndex;
      _pcm.clear();

      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // Do not aggressively alter Arabic phonetic cues before Tajweed
        // analysis. Sanad performs its own acoustic measurements server-side.
        noiseSuppress: false,
        echoCancel: false,
        autoGain: false,
      ));

      _audioSub = stream.listen((chunk) {
        if (_started && chunk.isNotEmpty) _pcm.addAll(chunk);
      });
      _started = true;
      return true;
    } catch (_) {
      await _cleanupRecorder();
      return false;
    }
  }

  Future<Map<String, dynamic>?> stop() async {
    if (!_started || _stopping) return null;
    _stopping = true;
    try {
      // Stop capture first, then wait for the final stream callback before
      // building the WAV. This prevents the last spoken word being truncated.
      try {
        await _recorder?.stop();
      } catch (_) {}
      await _audioSub?.cancel();
      _audioSub = null;
      _started = false;

      if (_pcm.length < 3200) {
        _emitError('Audio bohat chhoti hai. Ayat dobara parhein.');
        return null;
      }

      final wav = _pcmToWav(Uint8List.fromList(_pcm), 16000, 1, 16);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${_baseUrl.replaceFirst(RegExp(r'\/$'), '')}/grade'),
      );
      request.fields['surah'] = '$_chapter';
      request.fields['ayah'] = '$_verse';
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        wav,
        filename: 'recitation_${_chapter}_$_verse.wav',
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        _emitError(_serverError(body, streamed.statusCode));
        return null;
      }

      final decoded = _decodeJson(body);
      if (decoded == null) {
        _emitError('Tajweed server ne valid result nahi diya.');
        return null;
      }
      _results.add(decoded);
      return decoded;
    } on TimeoutException {
      _emitError('Tajweed analysis mein waqt zyada lag gaya. Dobara try karein.');
      return null;
    } on SocketException {
      _emitError('Tajweed server se connection nahi ho saka. Internet/server check karein.');
      return null;
    } catch (e) {
      _emitError('Tajweed analysis error: $e');
      return null;
    } finally {
      _pcm.clear();
      await _cleanupRecorder();
      _stopping = false;
    }
  }

  Map<String, dynamic>? _decodeJson(String body) {
    try {
      final value = _jsonDecode(body);
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    return null;
  }

  dynamic _jsonDecode(String body) {
    // Avoid another dependency: dart:convert is loaded lazily through this
    // helper import alias below.
    return jsonDecode(body);
  }

  String _serverError(String body, int status) {
    try {
      final value = jsonDecode(body);
      if (value is Map && value['detail'] != null) {
        return 'Tajweed server ($status): ${value['detail']}';
      }
    } catch (_) {}
    return 'Tajweed server error ($status).';
  }

  void _emitError(String message) {
    _results.add({'event': 'SANAD_ERROR', 'message': message});
  }

  Future<void> _cleanupRecorder() async {
    try {
      await _audioSub?.cancel();
    } catch (_) {}
    _audioSub = null;
    try {
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;
  }

  Uint8List _pcmToWav(Uint8List pcm, int sampleRate, int channels, int bits) {
    final byteRate = sampleRate * channels * bits ~/ 8;
    final blockAlign = channels * bits ~/ 8;
    final out = BytesBuilder(copy: false);
    void u16(int v) {
      out.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
    }
    void u32(int v) {
      out.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    }
    out.add('RIFF'.codeUnits);
    u32(36 + pcm.length);
    out.add('WAVE'.codeUnits);
    out.add('fmt '.codeUnits);
    u32(16);
    u16(1);
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bits);
    out.add('data'.codeUnits);
    u32(pcm.length);
    out.add(pcm);
    return out.takeBytes();
  }

  Future<void> dispose() async {
    if (_started) await stop();
    await _results.close();
  }
}


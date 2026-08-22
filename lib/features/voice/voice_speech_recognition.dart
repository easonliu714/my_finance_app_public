import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceSpeechStartResult {
  const VoiceSpeechStartResult({
    required this.started,
    this.message = '',
  });

  final bool started;
  final String message;
}

typedef VoiceSpeechResultCallback = void Function(String words, bool isFinal);
typedef VoiceSpeechStatusCallback = void Function(String status);
typedef VoiceSpeechErrorCallback = void Function(String message);

abstract class VoiceSpeechRecognitionPort {
  bool get isListening;

  Future<VoiceSpeechStartResult> start({
    required VoiceSpeechResultCallback onResult,
    required VoiceSpeechStatusCallback onStatus,
    required VoiceSpeechErrorCallback onError,
  });

  Future<void> stop();
  Future<void> cancel();
}

class PlatformVoiceSpeechRecognitionPort implements VoiceSpeechRecognitionPort {
  PlatformVoiceSpeechRecognitionPort({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;
  bool _available = false;
  bool _manualSessionActive = false;
  bool _restartScheduled = false;
  int _sessionGeneration = 0;
  String _committedWords = '';
  String _cycleWords = '';
  VoiceSpeechResultCallback? _onResult;
  VoiceSpeechStatusCallback? _onStatus;
  VoiceSpeechErrorCallback? _onError;

  @override
  bool get isListening => _manualSessionActive;

  @override
  Future<VoiceSpeechStartResult> start({
    required VoiceSpeechResultCallback onResult,
    required VoiceSpeechStatusCallback onStatus,
    required VoiceSpeechErrorCallback onError,
  }) async {
    _onResult = onResult;
    _onStatus = onStatus;
    _onError = onError;

    try {
      if (!_initialized) {
        _available = await _speech.initialize(
          onStatus: _handleStatus,
          onError: _handleError,
        );
        _initialized = true;
      }
      if (!_available) {
        return const VoiceSpeechStartResult(
          started: false,
          message: '語音辨識不可用或麥克風權限未授權；你仍可直接輸入文字。',
        );
      }

      if (_manualSessionActive) {
        return const VoiceSpeechStartResult(started: true);
      }

      _manualSessionActive = true;
      _restartScheduled = false;
      _sessionGeneration += 1;
      _committedWords = '';
      _cycleWords = '';
      final generation = _sessionGeneration;
      final started = await _startPlatformCycle(generation);
      if (!started) {
        _manualSessionActive = false;
        return const VoiceSpeechStartResult(
          started: false,
          message: '語音服務沒有開始聆聽；請改用文字輸入或稍後重試。',
        );
      }
      return const VoiceSpeechStartResult(started: true);
    } catch (_) {
      _manualSessionActive = false;
      return const VoiceSpeechStartResult(
        started: false,
        message: '無法啟動語音辨識；請改用文字輸入或稍後重試。',
      );
    }
  }

  Future<bool> _startPlatformCycle(int generation) async {
    if (!_manualSessionActive || generation != _sessionGeneration) {
      return false;
    }

    try {
      final locales = await _speech.locales();
      String? localeId;
      for (final locale in locales) {
        final normalized = locale.localeId.toLowerCase().replaceAll('-', '_');
        if (normalized == 'zh_tw' || normalized.startsWith('zh_hant')) {
          localeId = locale.localeId;
          break;
        }
      }

      _cycleWords = '';
      await _speech.listen(
        onResult: _handleResult,
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 30),
        ),
      );
      if (_manualSessionActive && generation == _sessionGeneration) {
        _onStatus?.call('listening');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _commitCycleWords();
    _manualSessionActive = false;
    _restartScheduled = false;
    _sessionGeneration += 1;
    try {
      await _speech.stop();
    } catch (_) {
      // Fail closed: transcript text already visible in the review page remains
      // editable even if the platform speech service cannot stop cleanly.
    }
  }

  @override
  Future<void> cancel() async {
    _commitCycleWords();
    _manualSessionActive = false;
    _restartScheduled = false;
    _sessionGeneration += 1;
    try {
      await _speech.cancel();
    } catch (_) {
      // Cancellation must never create a transaction or clear user-entered text.
    }
  }

  void _handleResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;
    _cycleWords = words;
    final combined = _joinSegments(_committedWords, words);
    _onResult?.call(combined, false);
    if (result.finalResult) {
      _committedWords = combined;
      _cycleWords = '';
    }
  }

  void _handleStatus(String status) {
    final normalized = status.toLowerCase();
    final finished = normalized.contains('done') ||
        normalized.contains('notlistening') ||
        normalized.contains('not listening');

    if (_manualSessionActive && finished) {
      _commitCycleWords();
      _onStatus?.call('restarting');
      _scheduleRestart();
      return;
    }
    _onStatus?.call(status);
  }

  void _handleError(SpeechRecognitionError error) {
    final normalized = error.errorMsg.toLowerCase();
    final recoverableSilence = normalized.contains('no_match') ||
        normalized.contains('speech_timeout') ||
        normalized.contains('speech timeout');
    if (_manualSessionActive && recoverableSilence) {
      _commitCycleWords();
      _onStatus?.call('restarting');
      _scheduleRestart();
      return;
    }

    _manualSessionActive = false;
    _restartScheduled = false;
    _sessionGeneration += 1;
    _onError?.call(_localizedError(error.errorMsg));
  }

  void _scheduleRestart() {
    if (!_manualSessionActive || _restartScheduled) return;
    _restartScheduled = true;
    final generation = _sessionGeneration;
    Future<void>.delayed(const Duration(milliseconds: 250), () async {
      _restartScheduled = false;
      if (!_manualSessionActive || generation != _sessionGeneration) return;
      final restarted = await _startPlatformCycle(generation);
      if (restarted || !_manualSessionActive || generation != _sessionGeneration) {
        return;
      }
      _manualSessionActive = false;
      _sessionGeneration += 1;
      _onError?.call('語音服務無法繼續聆聽；目前文字已保留，可直接修正後解析。');
    });
  }

  void _commitCycleWords() {
    final words = _cycleWords.trim();
    if (words.isEmpty) return;
    _committedWords = _joinSegments(_committedWords, words);
    _cycleWords = '';
    _onResult?.call(_committedWords, false);
  }

  static String _joinSegments(String prefix, String segment) {
    final left = prefix.trim();
    final right = segment.trim();
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    if (left == right || left.endsWith(right)) return left;
    if (right.startsWith(left)) return right;
    if (RegExp(r'[，、。；;,.!?！？]$').hasMatch(left)) {
      return '$left$right';
    }
    return '$left，$right';
  }

  static String _localizedError(String error) {
    final normalized = error.toLowerCase();
    if (normalized.contains('permission') || normalized.contains('denied')) {
      return '麥克風或語音辨識權限未授權；你仍可直接輸入文字。';
    }
    if (normalized.contains('network')) {
      return '語音服務目前無法連線；請改用文字輸入或稍後重試。';
    }
    if (normalized.contains('no_match')) {
      return '沒有辨識到清楚語句；請重試或直接輸入文字。';
    }
    return '語音辨識未完成；請重試或直接輸入文字。';
  }
}

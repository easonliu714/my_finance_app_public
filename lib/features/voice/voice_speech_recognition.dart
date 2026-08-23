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

  static const int _maxRestartAttempts = 6;
  static const Duration _segmentResetGap = Duration(milliseconds: 1200);

  final SpeechToText _speech;
  bool _initialized = false;
  bool _available = false;
  bool _manualSessionActive = false;
  bool _restartScheduled = false;
  int _restartAttempt = 0;
  int _sessionGeneration = 0;
  String _committedWords = '';
  String _cycleWords = '';
  DateTime? _lastResultAt;
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
      _restartAttempt = 0;
      _sessionGeneration += 1;
      _committedWords = '';
      _cycleWords = '';
      _lastResultAt = null;
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
      _lastResultAt = null;
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
    _restartAttempt = 0;
    _lastResultAt = null;
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
    _restartAttempt = 0;
    _lastResultAt = null;
    _sessionGeneration += 1;
    try {
      await _speech.cancel();
    } catch (_) {
      // Cancellation must never create a transaction or clear user-entered text.
    }
  }

  void _handleResult(SpeechRecognitionResult result) {
    if (!_manualSessionActive) return;
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;

    final now = DateTime.now();
    final previous = _cycleWords.trim();
    if (_shouldPromotePreviousPartial(previous, words, now)) {
      _committedWords = _joinSegments(_committedWords, previous);
      _cycleWords = '';
    }

    _restartAttempt = 0;
    _cycleWords = words;
    _lastResultAt = now;
    final combined = _joinSegments(_committedWords, words);
    _onResult?.call(combined, false);
    if (result.finalResult) {
      _committedWords = combined;
      _cycleWords = '';
      _lastResultAt = null;
    }
  }

  bool _shouldPromotePreviousPartial(
    String previous,
    String incoming,
    DateTime now,
  ) {
    if (previous.isEmpty || incoming.isEmpty) return false;
    if (_sameHypothesis(previous, incoming)) return false;
    final last = _lastResultAt;
    if (last == null) return false;
    return now.difference(last) >= _segmentResetGap;
  }

  static bool _sameHypothesis(String left, String right) {
    final a = _normalizeHypothesis(left);
    final b = _normalizeHypothesis(right);
    if (a.isEmpty || b.isEmpty) return true;
    if (a == b || a.startsWith(b) || b.startsWith(a)) return true;

    final limit = a.length < b.length ? a.length : b.length;
    var prefix = 0;
    while (prefix < limit && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
      prefix += 1;
    }
    if (prefix >= 3) return true;
    return limit <= 4 && prefix >= 2;
  }

  static String _normalizeHypothesis(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s，、。；;,.!?！？：:]'), '');
  }

  void _handleStatus(String status) {
    if (!_manualSessionActive) return;

    final normalized = status.toLowerCase();
    final finished = normalized.contains('done') ||
        normalized.contains('notlistening') ||
        normalized.contains('not listening');

    if (finished) {
      _commitCycleWords();
      _onStatus?.call('restarting');
      _scheduleRestart();
      return;
    }
    _onStatus?.call(status);
  }

  void _handleError(SpeechRecognitionError error) {
    // Android can deliver a trailing callback after an explicit stop/cancel.
    // Once the user session is inactive those callbacks must not resurrect or
    // invalidate the completed transcript.
    if (!_manualSessionActive) return;

    final normalized = error.errorMsg.toLowerCase();
    final recoverableSilence = normalized.contains('no_match') ||
        normalized.contains('speech_timeout') ||
        normalized.contains('speech timeout');
    final recoverableReleaseRace = normalized.contains('busy') ||
        normalized.contains('error_client') ||
        normalized.contains('error client');

    if (recoverableSilence || recoverableReleaseRace) {
      _commitCycleWords();
      if (recoverableReleaseRace) {
        _restartAttempt += 1;
      }
      _onStatus?.call('restarting');
      _scheduleRestart();
      return;
    }

    _endManualSessionWithError(_localizedError(error.errorMsg));
  }

  void _scheduleRestart() {
    if (!_manualSessionActive || _restartScheduled) return;
    if (_restartAttempt >= _maxRestartAttempts) {
      _endManualSessionWithError(
        '語音服務持續忙碌，無法穩定恢復聆聽；目前文字已保留，可直接修正後解析。',
      );
      return;
    }

    _restartScheduled = true;
    final generation = _sessionGeneration;
    final delay = _restartDelay(_restartAttempt);
    Future<void>.delayed(delay, () async {
      if (!_manualSessionActive || generation != _sessionGeneration) {
        _restartScheduled = false;
        return;
      }

      // A native endpoint/error callback can arrive before Android has fully
      // released SpeechRecognizer. Do not race a new listen() against an
      // instance that still reports itself active.
      if (_speech.isListening) {
        _restartScheduled = false;
        _restartAttempt += 1;
        _onStatus?.call('restarting');
        _scheduleRestart();
        return;
      }

      _restartScheduled = false;
      final restarted = await _startPlatformCycle(generation);
      if (restarted || !_manualSessionActive || generation != _sessionGeneration) {
        return;
      }

      _restartAttempt += 1;
      _onStatus?.call('restarting');
      _scheduleRestart();
    });
  }

  static Duration _restartDelay(int attempt) {
    if (attempt <= 0) return const Duration(milliseconds: 600);
    if (attempt == 1) return const Duration(milliseconds: 900);
    if (attempt == 2) return const Duration(milliseconds: 1200);
    if (attempt == 3) return const Duration(milliseconds: 1600);
    if (attempt == 4) return const Duration(milliseconds: 2000);
    return const Duration(milliseconds: 2500);
  }

  void _endManualSessionWithError(String message) {
    _manualSessionActive = false;
    _restartScheduled = false;
    _restartAttempt = 0;
    _lastResultAt = null;
    _sessionGeneration += 1;
    _onError?.call(message);
  }

  void _commitCycleWords() {
    final words = _cycleWords.trim();
    if (words.isEmpty) return;
    _committedWords = _joinSegments(_committedWords, words);
    _cycleWords = '';
    _lastResultAt = null;
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

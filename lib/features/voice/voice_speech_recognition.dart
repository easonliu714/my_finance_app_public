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
  VoiceSpeechResultCallback? _onResult;
  VoiceSpeechStatusCallback? _onStatus;
  VoiceSpeechErrorCallback? _onError;

  @override
  bool get isListening => _speech.isListening;

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

      final locales = await _speech.locales();
      String? localeId;
      for (final locale in locales) {
        final normalized = locale.localeId.toLowerCase().replaceAll('-', '_');
        if (normalized == 'zh_tw' || normalized.startsWith('zh_hant')) {
          localeId = locale.localeId;
          break;
        }
      }

      await _speech.listen(
        onResult: _handleResult,
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
      );
      if (!_speech.isListening) {
        return const VoiceSpeechStartResult(
          started: false,
          message: '語音服務沒有開始聆聽；請改用文字輸入或稍後重試。',
        );
      }
      return const VoiceSpeechStartResult(started: true);
    } catch (_) {
      return const VoiceSpeechStartResult(
        started: false,
        message: '無法啟動語音辨識；請改用文字輸入或稍後重試。',
      );
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {
      // Fail closed: transcript text already visible in the review page remains
      // editable even if the platform speech service cannot stop cleanly.
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {
      // Cancellation must never create a transaction or clear user-entered text.
    }
  }

  void _handleResult(SpeechRecognitionResult result) {
    _onResult?.call(result.recognizedWords, result.finalResult);
  }

  void _handleStatus(String status) {
    _onStatus?.call(status);
  }

  void _handleError(SpeechRecognitionError error) {
    _onError?.call(_localizedError(error.errorMsg));
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

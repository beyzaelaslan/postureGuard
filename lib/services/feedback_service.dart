import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../models/posture_status.dart';
import '../services/posture_analyzer.dart';

class FeedbackService {
  final FlutterTts _tts = FlutterTts();

  // Voice alert state
  static const int _badPostureThresholdSeconds = 10;
  static const int _alertCooldownSeconds = 30;
  int _consecutiveBadSeconds = 0;
  DateTime? _lastAlertTime;

  // Score tracking — rolling window of last 30 frames (~1 second at 30fps)
  static const int _scoreWindowSize = 30;
  final Queue<bool> _scoreWindow = Queue<bool>();

  // Streak tracking
  int _goodStreakSeconds = 0;
  int _consecutiveBadFramesForReset = 0;
  static const int _badResetThresholdFrames = 90; // ~3 seconds at 30fps
  DateTime? _lastStreakUpdateTime;

  // Per-second status tracking for alerts
  DateTime? _lastSecondCheck;
  int _badFramesThisSecond = 0;
  int _totalFramesThisSecond = 0;

  double get scorePercent {
    if (_scoreWindow.isEmpty) return 1.0;
    final goodCount = _scoreWindow.where((g) => g).length;
    return goodCount / _scoreWindow.length;
  }

  int get goodStreakMinutes => _goodStreakSeconds ~/ 60;
  int get goodStreakSeconds => _goodStreakSeconds;

  Future<void> initialize() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  /// Called every frame with the latest analysis result.
  void onFrame(PostureAnalysisResult result) {
    final isGood = result.status == PostureStatus.good;

    // Update score window
    _scoreWindow.addLast(isGood);
    if (_scoreWindow.length > _scoreWindowSize) {
      _scoreWindow.removeFirst();
    }

    // Update streak
    _updateStreak(isGood);

    // Track per-second bad posture for voice alerts
    _trackBadPosture(result);
  }

  void _updateStreak(bool isGood) {
    if (isGood) {
      _consecutiveBadFramesForReset = 0;

      // Increment streak once per second
      final now = DateTime.now();
      if (_lastStreakUpdateTime == null ||
          now.difference(_lastStreakUpdateTime!).inMilliseconds >= 1000) {
        _lastStreakUpdateTime = now;
        _goodStreakSeconds++;
      }
    } else {
      _consecutiveBadFramesForReset++;
      if (_consecutiveBadFramesForReset >= _badResetThresholdFrames) {
        _goodStreakSeconds = 0;
        _lastStreakUpdateTime = null;
      }
    }
  }

  void _trackBadPosture(PostureAnalysisResult result) {
    final now = DateTime.now();

    // Reset per-second counters each second
    if (_lastSecondCheck == null ||
        now.difference(_lastSecondCheck!).inMilliseconds >= 1000) {
      // Evaluate the previous second
      if (_lastSecondCheck != null) {
        final wasBadSecond =
            _totalFramesThisSecond > 0 &&
            (_badFramesThisSecond / _totalFramesThisSecond) > 0.5;

        if (wasBadSecond) {
          _consecutiveBadSeconds++;
        } else {
          _consecutiveBadSeconds = 0;
        }

        // Fire voice alert after threshold
        if (_consecutiveBadSeconds >= _badPostureThresholdSeconds) {
          _tryFireAlert(result);
        }
      }

      _lastSecondCheck = now;
      _badFramesThisSecond = 0;
      _totalFramesThisSecond = 0;
    }

    _totalFramesThisSecond++;
    if (result.status == PostureStatus.bad) {
      _badFramesThisSecond++;
    }
  }

  void _tryFireAlert(PostureAnalysisResult result) {
    final now = DateTime.now();

    // Check cooldown
    if (_lastAlertTime != null &&
        now.difference(_lastAlertTime!).inSeconds < _alertCooldownSeconds) {
      return;
    }

    _lastAlertTime = now;
    _consecutiveBadSeconds = 0;

    // Speak the first violation message
    final messages = result.violationMessages;
    if (messages.isNotEmpty) {
      _speak(messages.first);
    }

    // Haptic vibration
    _vibrate();
  }

  Future<void> _speak(String message) async {
    try {
      await _tts.speak(message);
    } catch (e) {
      debugPrint('FeedbackService: TTS error: $e');
    }
  }

  Future<void> _vibrate() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(duration: 200);
      }
    } catch (e) {
      debugPrint('FeedbackService: Vibration error: $e');
    }
  }

  void reset() {
    _scoreWindow.clear();
    _consecutiveBadSeconds = 0;
    _lastAlertTime = null;
    _goodStreakSeconds = 0;
    _consecutiveBadFramesForReset = 0;
    _lastStreakUpdateTime = null;
    _lastSecondCheck = null;
    _badFramesThisSecond = 0;
    _totalFramesThisSecond = 0;
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}

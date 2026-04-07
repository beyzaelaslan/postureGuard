import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/calibration_data.dart';
import '../models/posture_status.dart';
import '../services/camera_service.dart';
import '../services/calibration_service.dart';
import '../services/database_service.dart';
import '../services/detection_service.dart';
import '../services/feedback_service.dart';
import '../services/posture_analyzer.dart';
import '../widgets/ambient_border.dart';
import '../widgets/camera_preview.dart' show CameraFeedView;
import '../widgets/score_meter.dart';
import '../widgets/skeleton_overlay.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final DetectionService _detectionService = DetectionService();
  final FeedbackService _feedbackService = FeedbackService();

  bool _isLoading = true;
  String? _error;

  CalibrationData? _calibration;
  PostureAnalyzer? _analyzer;

  NormalizedLandmarks? _currentLandmarks;
  PostureStatus _currentStatus = PostureStatus.good;
  PostureAnalysisResult _currentResult = PostureAnalysisResult.good;

  // Session logging
  late final String _sessionId;
  Timer? _logTimer;
  bool _isEnding = false;

  // Elapsed time
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _elapsedTimer;
  String _elapsedText = '00:00';

  // Pose lost tracking
  bool _poseLost = false;
  DateTime? _lastPoseTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep screen awake during session
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _init();
  }

  Future<void> _init() async {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      _calibration = await CalibrationService.load();
      if (_calibration == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'No calibration data found. Please calibrate first.';
          });
        }
        return;
      }
      _analyzer = PostureAnalyzer(_calibration!);
      await _feedbackService.initialize();

      await _cameraService.initialize();
      _startDetection();
      _startLogging();
      _startElapsedTimer();
      _stopwatch.start();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Initialization error: $e';
        });
      }
    }
  }

  void _startLogging() {
    _logTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      DatabaseService.logEvent(
        sessionId: _sessionId,
        status: _currentStatus,
      );
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = _stopwatch.elapsed;
      setState(() {
        _elapsedText =
            '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
      });

      // Check if pose has been lost for more than 3 seconds
      if (_lastPoseTime != null) {
        final timeSincePose =
            DateTime.now().difference(_lastPoseTime!).inSeconds;
        final lost = timeSincePose > 3;
        if (lost != _poseLost && mounted) {
          setState(() => _poseLost = lost);
        }
      }
    });
  }

  void _startDetection() {
    _cameraService.startImageStream((CameraImage image) async {
      final landmarks = await _detectionService.processFrame(
        image,
        _cameraService.cameraDescription!,
      );

      if (landmarks != null && mounted && _analyzer != null) {
        _lastPoseTime = DateTime.now();
        final result = _analyzer!.analyze(landmarks);
        _feedbackService.onFrame(result);
        setState(() {
          _currentLandmarks = landmarks;
          _currentStatus = result.status;
          _currentResult = result;
          _poseLost = false;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_cameraService.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopwatch.stop();
      _cameraService.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _stopwatch.start();
      _init();
    }
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _elapsedTimer?.cancel();
    _stopwatch.stop();
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    _detectionService.dispose();
    _feedbackService.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    return await _showEndConfirmation() ?? false;
  }

  Future<bool?> _showEndConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session?'),
        content:
            const Text('Your posture data will be saved and summarized.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  Future<void> _endSession() async {
    final confirmed = await _showEndConfirmation();
    if (confirmed != true) return;

    if (_isEnding) return;
    _isEnding = true;
    _logTimer?.cancel();
    _elapsedTimer?.cancel();
    _stopwatch.stop();

    await _cameraService.stopImageStream();

    final summary = await DatabaseService.endSession(_sessionId);

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/summary', arguments: summary);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use — WillPopScope needed for back button guard
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Starting session...',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera feed with skeleton overlay
          CameraFeedView(
            controller: _cameraService.controller!,
            overlays: [
              if (_currentLandmarks != null)
                SkeletonOverlay(
                  landmarks: _currentLandmarks!,
                  status: _currentStatus,
                ),
            ],
          ),

          // Ambient screen border
          AmbientBorder(status: _currentStatus),

          // Pose lost warning
          if (_poseLost)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_search, color: Colors.orange, size: 48),
                    SizedBox(height: 12),
                    Text(
                      'Pose Lost',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Make sure your face and shoulders\nare visible to the camera',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          // Top HUD: status + streak + elapsed
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Elapsed time
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer,
                              color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            _elapsedText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Posture status badge
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _currentStatus.color.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Streak
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_fire_department,
                          color: Colors.orange, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _streakText(),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Violation details
                if (_currentResult.violationCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _currentResult.violationMessages.join(' | '),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),

          // Score meter
          Positioned(
            bottom: 145,
            left: 0,
            right: 0,
            child: ScoreMeter(score: _feedbackService.scorePercent),
          ),

          // Rule indicator chips
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: _buildRuleIndicators(),
          ),

          // End session button
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isEnding ? null : _endSession,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.red.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _isEnding ? 'Saving...' : 'End Session',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusText() {
    if (_currentLandmarks == null) return 'Looking for pose...';
    switch (_currentStatus) {
      case PostureStatus.good:
        return 'GOOD POSTURE';
      case PostureStatus.warning:
        return 'WARNING — 1 issue';
      case PostureStatus.bad:
        return 'BAD POSTURE — ${_currentResult.violationCount} issues';
    }
  }

  String _streakText() {
    final mins = _feedbackService.goodStreakMinutes;
    final secs = _feedbackService.goodStreakSeconds % 60;
    if (mins > 0) {
      return '$mins min $secs sec streak';
    }
    return '$secs sec streak';
  }

  Widget _buildRuleIndicators() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        _ruleChip('Shoulders', !_currentResult.shoulderAsymmetry),
        _ruleChip('Head Tilt', !_currentResult.headTilt),
        _ruleChip('Hunching', !_currentResult.shoulderRounding),
        _ruleChip('Head Drop', !_currentResult.headDrop),
      ],
    );
  }

  Widget _ruleChip(String label, bool passing) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: passing
            ? Colors.green.withValues(alpha: 0.6)
            : Colors.red.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            passing ? Icons.check : Icons.close,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

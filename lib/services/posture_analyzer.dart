import '../models/calibration_data.dart';
import '../models/posture_status.dart';
import '../services/detection_service.dart';

/// Describes which of the 4 posture rules are currently violated.
class PostureAnalysisResult {
  final PostureStatus status;
  final bool shoulderAsymmetry;
  final bool headTilt;
  final bool shoulderRounding;
  final bool headDrop;

  const PostureAnalysisResult({
    required this.status,
    required this.shoulderAsymmetry,
    required this.headTilt,
    required this.shoulderRounding,
    required this.headDrop,
  });

  int get violationCount =>
      (shoulderAsymmetry ? 1 : 0) +
      (headTilt ? 1 : 0) +
      (shoulderRounding ? 1 : 0) +
      (headDrop ? 1 : 0);

  /// Human-readable list of current violations for voice alerts.
  List<String> get violationMessages {
    final messages = <String>[];
    if (shoulderAsymmetry) messages.add('Your shoulders are uneven');
    if (headTilt) messages.add('Your head is tilting');
    if (shoulderRounding) messages.add('Your shoulders are rounding');
    if (headDrop) messages.add('Your phone is too low');
    return messages;
  }

  static const good = PostureAnalysisResult(
    status: PostureStatus.good,
    shoulderAsymmetry: false,
    headTilt: false,
    shoulderRounding: false,
    headDrop: false,
  );
}

class PostureAnalyzer {
  final CalibrationData calibration;

  const PostureAnalyzer(this.calibration);

  /// Analyze current landmarks against the personal calibration baseline.
  PostureAnalysisResult analyze(NormalizedLandmarks landmarks) {
    // Rule 1: Shoulder symmetry
    // abs(left shoulder Y - right shoulder Y) > threshold
    final shoulderAsymmetry =
        (landmarks.leftShoulderY - landmarks.rightShoulderY).abs() >
            calibration.shoulderSymmetryThreshold;

    // Rule 2: Head tilt (ears)
    // abs(left ear Y - right ear Y) > threshold
    final headTilt = (landmarks.leftEarY - landmarks.rightEarY).abs() >
        calibration.headTiltThreshold;

    // Rule 3: Shoulder rounding (hunching)
    // current shoulder width < threshold (shoulders collapsing inward)
    final shoulderRounding =
        landmarks.shoulderWidth < calibration.shoulderWidthThreshold;

    // Rule 4: Head drop (phone too low)
    // nose Y has dropped significantly below baseline
    // (Y increases downward, so current > baseline means dropped)
    final headDrop = (landmarks.noseY - calibration.noseY) >
        calibration.headDropThreshold;

    final violations = (shoulderAsymmetry ? 1 : 0) +
        (headTilt ? 1 : 0) +
        (shoulderRounding ? 1 : 0) +
        (headDrop ? 1 : 0);

    return PostureAnalysisResult(
      status: PostureStatus.fromViolationCount(violations),
      shoulderAsymmetry: shoulderAsymmetry,
      headTilt: headTilt,
      shoulderRounding: shoulderRounding,
      headDrop: headDrop,
    );
  }
}

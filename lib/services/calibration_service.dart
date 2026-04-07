import 'package:shared_preferences/shared_preferences.dart';
import '../models/calibration_data.dart';
import '../services/detection_service.dart';

class CalibrationService {
  static const _prefix = 'calibration_';

  final List<NormalizedLandmarks> _samples = [];

  void addSample(NormalizedLandmarks landmarks) {
    _samples.add(landmarks);
  }

  int get sampleCount => _samples.length;

  void reset() {
    _samples.clear();
  }

  /// Compute calibration baseline by averaging all collected samples.
  /// Returns null if no samples were collected.
  CalibrationData? computeBaseline() {
    if (_samples.isEmpty) return null;

    final n = _samples.length.toDouble();

    double sumNoseX = 0, sumNoseY = 0;
    double sumLeftEarY = 0, sumRightEarY = 0;
    double sumLeftShoulderX = 0, sumLeftShoulderY = 0;
    double sumRightShoulderX = 0, sumRightShoulderY = 0;

    for (final s in _samples) {
      sumNoseX += s.noseX;
      sumNoseY += s.noseY;
      sumLeftEarY += s.leftEarY;
      sumRightEarY += s.rightEarY;
      sumLeftShoulderX += s.leftShoulderX;
      sumLeftShoulderY += s.leftShoulderY;
      sumRightShoulderX += s.rightShoulderX;
      sumRightShoulderY += s.rightShoulderY;
    }

    final avgLeftShoulderX = sumLeftShoulderX / n;
    final avgRightShoulderX = sumRightShoulderX / n;
    final avgShoulderWidth = (avgRightShoulderX - avgLeftShoulderX).abs();

    // Derive personal thresholds from baseline measurements.
    // Shoulder symmetry: allow ~50% of the baseline ear difference as tolerance
    final baselineEarDiff = ((sumLeftEarY / n) - (sumRightEarY / n)).abs();
    final baselineShoulderDiff =
        ((sumLeftShoulderY / n) - (sumRightShoulderY / n)).abs();

    return CalibrationData(
      noseX: sumNoseX / n,
      noseY: sumNoseY / n,
      leftEarY: sumLeftEarY / n,
      rightEarY: sumRightEarY / n,
      leftShoulderX: avgLeftShoulderX,
      leftShoulderY: sumLeftShoulderY / n,
      rightShoulderX: avgRightShoulderX,
      rightShoulderY: sumRightShoulderY / n,
      shoulderWidth: avgShoulderWidth,
      // Thresholds: baseline natural variance + fixed tolerance
      shoulderSymmetryThreshold: baselineShoulderDiff + 0.05,
      headTiltThreshold: baselineEarDiff + 0.04,
      shoulderWidthThreshold: avgShoulderWidth * 0.70, // 30% narrower = hunching
      headDropThreshold: 0.10,
    );
  }

  /// Save calibration data to shared_preferences.
  Future<void> save(CalibrationData data) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in data.toMap().entries) {
      await prefs.setDouble('$_prefix${entry.key}', entry.value);
    }
  }

  /// Load calibration data from shared_preferences.
  /// Returns null if no calibration has been saved.
  static Future<CalibrationData?> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if calibration exists
    if (!prefs.containsKey('${_prefix}noseX')) return null;

    final map = <String, double>{};
    for (final key in [
      'noseX', 'noseY',
      'leftEarY', 'rightEarY',
      'leftShoulderX', 'leftShoulderY',
      'rightShoulderX', 'rightShoulderY',
      'shoulderWidth',
      'shoulderSymmetryThreshold', 'headTiltThreshold',
      'shoulderWidthThreshold', 'headDropThreshold',
    ]) {
      final value = prefs.getDouble('$_prefix$key');
      if (value == null) return null;
      map[key] = value;
    }

    return CalibrationData.fromMap(map);
  }

  /// Clear saved calibration data.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

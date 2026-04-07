class CalibrationData {
  final double noseX;
  final double noseY;
  final double leftEarY;
  final double rightEarY;
  final double leftShoulderX;
  final double leftShoulderY;
  final double rightShoulderX;
  final double rightShoulderY;
  final double shoulderWidth;

  // Thresholds derived from calibration
  final double shoulderSymmetryThreshold;
  final double headTiltThreshold;
  final double shoulderWidthThreshold;
  final double headDropThreshold;

  const CalibrationData({
    required this.noseX,
    required this.noseY,
    required this.leftEarY,
    required this.rightEarY,
    required this.leftShoulderX,
    required this.leftShoulderY,
    required this.rightShoulderX,
    required this.rightShoulderY,
    required this.shoulderWidth,
    this.shoulderSymmetryThreshold = 0.05,
    this.headTiltThreshold = 0.04,
    this.shoulderWidthThreshold = 0.25,
    this.headDropThreshold = 0.10,
  });

  Map<String, double> toMap() => {
        'noseX': noseX,
        'noseY': noseY,
        'leftEarY': leftEarY,
        'rightEarY': rightEarY,
        'leftShoulderX': leftShoulderX,
        'leftShoulderY': leftShoulderY,
        'rightShoulderX': rightShoulderX,
        'rightShoulderY': rightShoulderY,
        'shoulderWidth': shoulderWidth,
        'shoulderSymmetryThreshold': shoulderSymmetryThreshold,
        'headTiltThreshold': headTiltThreshold,
        'shoulderWidthThreshold': shoulderWidthThreshold,
        'headDropThreshold': headDropThreshold,
      };

  factory CalibrationData.fromMap(Map<String, double> map) => CalibrationData(
        noseX: map['noseX']!,
        noseY: map['noseY']!,
        leftEarY: map['leftEarY']!,
        rightEarY: map['rightEarY']!,
        leftShoulderX: map['leftShoulderX']!,
        leftShoulderY: map['leftShoulderY']!,
        rightShoulderX: map['rightShoulderX']!,
        rightShoulderY: map['rightShoulderY']!,
        shoulderWidth: map['shoulderWidth']!,
        shoulderSymmetryThreshold:
            map['shoulderSymmetryThreshold'] ?? 0.05,
        headTiltThreshold: map['headTiltThreshold'] ?? 0.04,
        shoulderWidthThreshold: map['shoulderWidthThreshold'] ?? 0.25,
        headDropThreshold: map['headDropThreshold'] ?? 0.10,
      );
}

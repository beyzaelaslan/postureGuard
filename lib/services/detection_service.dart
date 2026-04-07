import 'dart:io';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// The 5 landmarks PostureGuard uses for posture analysis.
class PostureLandmarks {
  final PoseLandmark nose; // 0
  final PoseLandmark leftEar; // 7
  final PoseLandmark rightEar; // 8
  final PoseLandmark leftShoulder; // 11
  final PoseLandmark rightShoulder; // 12

  const PostureLandmarks({
    required this.nose,
    required this.leftEar,
    required this.rightEar,
    required this.leftShoulder,
    required this.rightShoulder,
  });

  /// Extract posture landmarks from a detected pose.
  /// Returns null if any required landmark is missing or has low confidence.
  static PostureLandmarks? fromPose(Pose pose, {double minLikelihood = 0.5}) {
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final leftEar = pose.landmarks[PoseLandmarkType.leftEar];
    final rightEar = pose.landmarks[PoseLandmarkType.rightEar];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (nose == null ||
        leftEar == null ||
        rightEar == null ||
        leftShoulder == null ||
        rightShoulder == null) {
      return null;
    }

    if (nose.likelihood < minLikelihood ||
        leftEar.likelihood < minLikelihood ||
        rightEar.likelihood < minLikelihood ||
        leftShoulder.likelihood < minLikelihood ||
        rightShoulder.likelihood < minLikelihood) {
      return null;
    }

    return PostureLandmarks(
      nose: nose,
      leftEar: leftEar,
      rightEar: rightEar,
      leftShoulder: leftShoulder,
      rightShoulder: rightShoulder,
    );
  }
}

/// Normalized landmark coordinates (0-1 range) for posture analysis.
/// Raw ML Kit coordinates are in image pixel space — this normalizes them
/// so posture rules work regardless of camera resolution.
class NormalizedLandmarks {
  final double noseX, noseY;
  final double leftEarX, leftEarY;
  final double rightEarX, rightEarY;
  final double leftShoulderX, leftShoulderY;
  final double rightShoulderX, rightShoulderY;

  const NormalizedLandmarks({
    required this.noseX,
    required this.noseY,
    required this.leftEarX,
    required this.leftEarY,
    required this.rightEarX,
    required this.rightEarY,
    required this.leftShoulderX,
    required this.leftShoulderY,
    required this.rightShoulderX,
    required this.rightShoulderY,
  });

  factory NormalizedLandmarks.fromRaw(
    PostureLandmarks raw,
    int imageWidth,
    int imageHeight,
  ) {
    final w = imageWidth.toDouble();
    final h = imageHeight.toDouble();

    return NormalizedLandmarks(
      noseX: raw.nose.x / w,
      noseY: raw.nose.y / h,
      leftEarX: raw.leftEar.x / w,
      leftEarY: raw.leftEar.y / h,
      rightEarX: raw.rightEar.x / w,
      rightEarY: raw.rightEar.y / h,
      leftShoulderX: raw.leftShoulder.x / w,
      leftShoulderY: raw.leftShoulder.y / h,
      rightShoulderX: raw.rightShoulder.x / w,
      rightShoulderY: raw.rightShoulder.y / h,
    );
  }

  double get shoulderWidth => (rightShoulderX - leftShoulderX).abs();
}

class DetectionService {
  late final PoseDetector _poseDetector;
  bool _isProcessing = false;

  DetectionService() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
  }

  /// Process a camera frame and return normalized landmarks.
  /// Returns null if no pose is detected or landmarks are insufficient.
  /// Skips frame if previous frame is still processing (drop strategy).
  Future<NormalizedLandmarks?> processFrame(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) return null;

      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isEmpty) return null;

      final landmarks = PostureLandmarks.fromPose(poses.first);
      if (landmarks == null) return null;

      return NormalizedLandmarks.fromRaw(
        landmarks,
        image.width,
        image.height,
      );
    } catch (e) {
      debugPrint('DetectionService: processFrame error: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _buildInputImage(CameraImage image, CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> dispose() async {
    await _poseDetector.close();
  }
}

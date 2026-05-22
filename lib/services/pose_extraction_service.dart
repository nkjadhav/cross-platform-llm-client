import 'dart:io';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;
import 'app_log_service.dart';

/// Extracts an OpenPose-style stick-figure image from a photo so it can be
/// fed to a ControlNet (OpenPose variant) as the `control_cond` reference.
///
/// MediaPipe Pose returns 33 landmarks; ControlNet OpenPose expects the
/// classic 18-keypoint body layout with a specific per-bone colour scheme,
/// so this service maps + remaps before rasterising on a black canvas.
class PoseExtractionService extends GetxService {
  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.single),
  );

  /// MediaPipe → OpenPose-18 mapping. `null` means computed (e.g. neck).
  static const List<PoseLandmarkType?> _mpForOpKp = [
    PoseLandmarkType.nose,
    null, // 1 — neck = midpoint(L/R shoulder)
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.rightAnkle,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightEye,
    PoseLandmarkType.leftEye,
    PoseLandmarkType.rightEar,
    PoseLandmarkType.leftEar,
  ];

  static const int _kpCount = 18;

  /// 17 bones connecting the 18 keypoints, matching OpenPose ordering.
  static const _bones = <List<int>>[
    [1, 2], [1, 5], [2, 3], [3, 4], [5, 6], [6, 7], [1, 8], [8, 9],
    [9, 10], [1, 11], [11, 12], [12, 13], [1, 0], [0, 14], [14, 16],
    [0, 15], [15, 17],
  ];

  /// Classic OpenPose RGB colour palette, one entry per bone.
  static const _boneColors = <List<int>>[
    [255, 0, 0], [255, 85, 0], [255, 170, 0], [255, 255, 0],
    [170, 255, 0], [85, 255, 0], [0, 255, 0], [0, 255, 85],
    [0, 255, 170], [0, 255, 255], [0, 170, 255], [0, 85, 255],
    [0, 0, 255], [85, 0, 255], [170, 0, 255], [255, 0, 255],
    [255, 0, 170],
  ];

  /// Per-keypoint dot colour, in the same OpenPose family.
  static const _kpColors = <List<int>>[
    [255, 0, 85], [255, 0, 0], [255, 85, 0], [255, 170, 0],
    [255, 255, 0], [170, 255, 0], [85, 255, 0], [0, 255, 0],
    [0, 255, 85], [0, 255, 170], [0, 255, 255], [0, 170, 255],
    [0, 85, 255], [0, 0, 255], [255, 0, 170], [170, 0, 255],
    [255, 0, 255], [85, 0, 255],
  ];

  /// Returns a (rgbBytes, width, height) record with a 512x512 OpenPose
  /// rendering, or null if no pose was detectable.
  Future<({Uint8List rgb, int width, int height})?> extractPoseRgb(
    String sourceImagePath, {
    int targetSize = 512,
  }) async {
    try {
      final inputImage = InputImage.fromFilePath(sourceImagePath);
      final poses = await _detector.processImage(inputImage);
      if (poses.isEmpty) {
        Get.find<AppLogService>()
            .warning('PoseExtractor: no pose detected in $sourceImagePath');
        return null;
      }
      final pose = poses.first;

      // Decode just to learn the source dimensions so we can normalise.
      final bytes = await File(sourceImagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final srcW = decoded.width;
      final srcH = decoded.height;

      // Resolve the 18 OpenPose-style keypoints into the [0,targetSize] space.
      final pts = List<List<double>?>.filled(_kpCount, null);
      for (var i = 0; i < _kpCount; i++) {
        final mp = _mpForOpKp[i];
        final p = mp == null
            ? _midpoint(
                pose.landmarks[PoseLandmarkType.leftShoulder],
                pose.landmarks[PoseLandmarkType.rightShoulder],
              )
            : _resolve(pose.landmarks[mp]);
        if (p == null) continue;
        pts[i] = [
          p[0] / srcW * targetSize,
          p[1] / srcH * targetSize,
        ];
      }

      // Black canvas — ControlNet OpenPose expects pose strokes on black.
      final canvas =
          img.Image(width: targetSize, height: targetSize, numChannels: 3);
      img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

      for (var i = 0; i < _bones.length; i++) {
        final a = pts[_bones[i][0]];
        final b = pts[_bones[i][1]];
        if (a == null || b == null) continue;
        final c = _boneColors[i];
        img.drawLine(
          canvas,
          x1: a[0].round(),
          y1: a[1].round(),
          x2: b[0].round(),
          y2: b[1].round(),
          color: img.ColorRgb8(c[0], c[1], c[2]),
          thickness: 4,
        );
      }
      for (var i = 0; i < _kpCount; i++) {
        final p = pts[i];
        if (p == null) continue;
        final c = _kpColors[i];
        img.fillCircle(
          canvas,
          x: p[0].round(),
          y: p[1].round(),
          radius: 4,
          color: img.ColorRgb8(c[0], c[1], c[2]),
        );
      }

      // Pack into tight RGB (no alpha).
      final rgb = Uint8List(targetSize * targetSize * 3);
      var idx = 0;
      for (final p in canvas) {
        rgb[idx++] = p.r.toInt();
        rgb[idx++] = p.g.toInt();
        rgb[idx++] = p.b.toInt();
      }
      return (rgb: rgb, width: targetSize, height: targetSize);
    } catch (e) {
      Get.find<AppLogService>().error('Pose extraction failed', details: e);
      return null;
    }
  }

  Future<void> close() => _detector.close();

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// 50% likelihood floor — noisier points muddy the ControlNet input more
  /// than just leaving them out.
  static const double _minLikelihood = 0.5;

  List<double>? _resolve(PoseLandmark? lm) {
    if (lm == null) return null;
    if (lm.likelihood < _minLikelihood) return null;
    return [lm.x, lm.y];
  }

  List<double>? _midpoint(PoseLandmark? a, PoseLandmark? b) {
    final p1 = _resolve(a);
    final p2 = _resolve(b);
    if (p1 == null || p2 == null) return null;
    return [(p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2];
  }
}

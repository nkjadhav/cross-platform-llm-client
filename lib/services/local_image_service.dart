import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:sd_flutter_android/sd_flutter_android.dart';
import '../core/constants.dart';
import 'hive_service.dart';
import 'pose_extraction_service.dart';

class LocalImageService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();

  final isModelLoaded = false.obs;
  final isLoadingModel = false.obs;
  final isGenerating = false.obs;
  final progress = 0.0.obs;
  final loadedModelName = ''.obs;

  String? get lastModelPath =>
      _hive.getSetting<String>(AppConstants.keyImageModelPath);
  String? get lastModelName =>
      _hive.getSetting<String>(AppConstants.keyImageModelName);

  Future<String> loadModel(String modelPath, {String? modelName}) async {
    if (isLoadingModel.value) return 'ERROR: Model is already loading.';
    
    try {
      if (isModelLoaded.value) {
        await unloadModel();
      }

      isLoadingModel.value = true;
      progress.value = 0.0;

      print('[LocalImageService] loadModel called with path: $modelPath');

      // Debug: check file existence and size from Dart side
      try {
        final file = File(modelPath);
        final exists = await file.exists();
        print('[LocalImageService] File exists: $exists');
        if (exists) {
          final length = await file.length();
          print('[LocalImageService] File size: $length bytes');
        }
      } catch (e) {
        print('[LocalImageService] File check error: $e');
      }

      // If the user has a ControlNet enabled with a downloaded checkpoint,
      // load it alongside the base model — sd.cpp wants both at ctx init.
      final controlNetEnabled =
          _hive.getSetting<bool>(AppConstants.keyControlNetEnabled,
                  defaultValue: false) ??
              false;
      final controlNetPath = controlNetEnabled
          ? _hive.getSetting<String>(AppConstants.keyControlNetPath) ?? ''
          : '';

      print('[LocalImageService] Calling SdFlutterAndroid.initModel...');
      final rawResult = await SdFlutterAndroid.initModelRaw(
        modelPath,
        controlNetPath: controlNetPath.isEmpty ? null : controlNetPath,
      );
      print('[LocalImageService] initModel raw result: $rawResult');

      final success = rawResult is bool ? rawResult : (rawResult is String && rawResult == 'true');

      if (success) {
        isModelLoaded.value = true;
        isLoadingModel.value = false;
        loadedModelName.value = modelName ?? modelPath.split('/').last;
        await _hive.setSetting(AppConstants.keyImageModelPath, modelPath);
        await _hive.setSetting(AppConstants.keyImageModelName, loadedModelName.value);
        return 'Image model loaded successfully.';
      } else {
        isModelLoaded.value = false;
        isLoadingModel.value = false;
        final errorDetail = rawResult is String ? rawResult : 'Model initialization failed.';
        return 'Could not load this model. Try CyberRealistic, Realistic Vision, or AbsoluteReality — these work reliably on most devices.\n\nTechnical detail: $errorDetail';
      }
    } catch (e) {
      isModelLoaded.value = false;
      isLoadingModel.value = false;
      return 'Could not load this model. Try CyberRealistic, Realistic Vision, or AbsoluteReality — these work reliably on most devices.\n\nTechnical detail: $e';
    }
  }

  Future<void> unloadModel() async {
    await SdFlutterAndroid.unloadModel();
    isModelLoaded.value = false;
    loadedModelName.value = '';
    await _hive.setSetting(AppConstants.keyImageModelPath, '');
    await _hive.setSetting(AppConstants.keyImageModelName, '');
  }

  Future<Uint8List?> generateImage({
    required String prompt,
    String? referenceImagePath,
    double? strength,
    void Function(int step, int totalSteps)? onProgress,
  }) async {
    if (!isModelLoaded.value) return null;
    if (isGenerating.value) return null;

    isGenerating.value = true;
    try {
      final steps = _hive.getSetting<int>(AppConstants.keyImageSteps,
          defaultValue: AppConstants.defaultImageSteps) ??
          AppConstants.defaultImageSteps;

      Uint8List? referenceRgb;
      int referenceWidth = 0;
      int referenceHeight = 0;
      Uint8List? controlRgb;
      int controlWidth = 0;
      int controlHeight = 0;

      final controlNetEnabled =
          _hive.getSetting<bool>(AppConstants.keyControlNetEnabled,
                  defaultValue: false) ??
              false;
      final controlNetLoaded = controlNetEnabled &&
          ((_hive.getSetting<String>(AppConstants.keyControlNetPath) ?? '')
              .isNotEmpty);

      if (referenceImagePath != null && referenceImagePath.isNotEmpty) {
        if (controlNetLoaded && Get.isRegistered<PoseExtractionService>()) {
          // Route the upload through pose extraction → ControlNet cond image.
          final pose = await Get.find<PoseExtractionService>()
              .extractPoseRgb(referenceImagePath);
          if (pose != null) {
            controlRgb = pose.rgb;
            controlWidth = pose.width;
            controlHeight = pose.height;
          } else {
            // Pose extraction failed — fall back to plain img2img.
            final prepared = await _prepareReferenceImage(referenceImagePath);
            if (prepared != null) {
              referenceRgb = prepared.rgbBytes;
              referenceWidth = prepared.width;
              referenceHeight = prepared.height;
            }
          }
        } else {
          final prepared = await _prepareReferenceImage(referenceImagePath);
          if (prepared != null) {
            referenceRgb = prepared.rgbBytes;
            referenceWidth = prepared.width;
            referenceHeight = prepared.height;
          }
        }
      }

      final effectiveStrength = strength ??
          _hive.getSetting<double>(AppConstants.keyImageStrength,
              defaultValue: AppConstants.defaultImageStrength) ??
          AppConstants.defaultImageStrength;
      final effectiveControlStrength = _hive.getSetting<double>(
              AppConstants.keyControlStrength,
              defaultValue: AppConstants.defaultControlStrength) ??
          AppConstants.defaultControlStrength;

      final rawBytes = await SdFlutterAndroid.generateImage(
        prompt,
        steps: steps,
        referenceImage: referenceRgb,
        referenceWidth: referenceWidth,
        referenceHeight: referenceHeight,
        strength: effectiveStrength,
        controlImage: controlRgb,
        controlWidth: controlWidth,
        controlHeight: controlHeight,
        controlStrength: effectiveControlStrength,
        onProgress: (step, total) {
          onProgress?.call(step, total);
        }
      );

      if (rawBytes == null) {
        isGenerating.value = false;
        return null;
      }

      // Convert raw RGB (512x512x3) to PNG
      // Note: This is computationally expensive in Dart, but necessary for now
      final image = img.Image.fromBytes(
        width: 512,
        height: 512,
        bytes: rawBytes.buffer,
        numChannels: 3,
      );
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      isGenerating.value = false;
      return pngBytes;
    } catch (e) {
      isGenerating.value = false;
      print('Native Generation Error: $e');
      return null;
    }
  }

  /// Decode an on-disk image, resize to 512x512, and return as raw RGB bytes
  /// matching the layout expected by `sd_image_t` on the JNI side.
  Future<_PreparedReference?> _prepareReferenceImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        print('[LocalImageService] Reference image not found: $path');
        return null;
      }
      final raw = await file.readAsBytes();
      final decoded = img.decodeImage(raw);
      if (decoded == null) {
        print('[LocalImageService] Could not decode reference image: $path');
        return null;
      }
      // SD 1.5 generates at 512x512; matching the reference avoids letterboxing
      // and keeps the strength parameter behaving predictably.
      const target = 512;
      final resized = decoded.width == target && decoded.height == target
          ? decoded
          : img.copyResize(decoded,
              width: target, height: target, interpolation: img.Interpolation.cubic);

      // Pack into tightly-packed RGB (no alpha) since sd_image_t expects channel=3.
      final rgb = Uint8List(target * target * 3);
      var i = 0;
      for (final p in resized) {
        rgb[i++] = p.r.toInt();
        rgb[i++] = p.g.toInt();
        rgb[i++] = p.b.toInt();
      }
      return _PreparedReference(rgb, target, target);
    } catch (e) {
      print('[LocalImageService] Reference image prep failed: $e');
      return null;
    }
  }
}

class _PreparedReference {
  final Uint8List rgbBytes;
  final int width;
  final int height;
  _PreparedReference(this.rgbBytes, this.width, this.height);
}

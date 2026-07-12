import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../models/video_job.dart';
import '../services/hive_service.dart';
import '../services/video_gen_service.dart';

/// Drives the Video Generation screen: prompt, base image, generation
/// parameters, the active job, and the history of past jobs.
class VideoGenController extends GetxController {
  final VideoGenService _service = Get.find<VideoGenService>();
  final HiveService _hive = Get.find<HiveService>();
  final _uuid = const Uuid();

  final promptController = TextEditingController();

  /// 'text' or 'image'.
  final mode = 'text'.obs;
  final sourceImagePath = RxnString();

  final provider = AppConstants.defaultVideoProvider.obs;
  final textModel = ''.obs;
  final imageModel = ''.obs;
  final aspectRatio = AppConstants.defaultVideoAspectRatio.obs;
  final duration = AppConstants.defaultVideoDuration.obs;

  final isGenerating = false.obs;
  final statusDetail = ''.obs;
  final activeJob = Rxn<VideoJob>();
  final history = <VideoJob>[].obs;

  bool get isConfigured => _service.isConfigured;

  String get currentModel =>
      mode.value == 'image' ? imageModel.value : textModel.value;

  List<Map<String, String>> get modelsForMode {
    final table = mode.value == 'image'
        ? AppConstants.videoImageModels
        : AppConstants.videoTextModels;
    return table[provider.value] ?? const [];
  }

  @override
  void onInit() {
    super.onInit();
    _restore();
    history.assignAll(_service.loadHistory());
  }

  @override
  void onClose() {
    promptController.dispose();
    super.onClose();
  }

  void _restore() {
    provider.value = _hive.getSetting(AppConstants.keyVideoProvider,
            defaultValue: AppConstants.defaultVideoProvider) ??
        AppConstants.defaultVideoProvider;
    aspectRatio.value = _hive.getSetting(AppConstants.keyVideoAspectRatio,
            defaultValue: AppConstants.defaultVideoAspectRatio) ??
        AppConstants.defaultVideoAspectRatio;
    duration.value = _hive.getSetting(AppConstants.keyVideoDuration,
            defaultValue: AppConstants.defaultVideoDuration) ??
        AppConstants.defaultVideoDuration;
    _ensureModelDefaults();
    textModel.value = _hive.getSetting(AppConstants.keyVideoTextModel) ??
        textModel.value;
    imageModel.value = _hive.getSetting(AppConstants.keyVideoImageModel) ??
        imageModel.value;
  }

  /// Ensure the selected model is valid for the current provider; fall back to
  /// the first curated model otherwise.
  void _ensureModelDefaults() {
    final texts = AppConstants.videoTextModels[provider.value] ?? const [];
    final images = AppConstants.videoImageModels[provider.value] ?? const [];
    final textIds = texts.map((m) => m['id']).toList();
    final imageIds = images.map((m) => m['id']).toList();
    if (!textIds.contains(textModel.value)) {
      textModel.value = texts.isNotEmpty ? texts.first['id']! : '';
    }
    if (!imageIds.contains(imageModel.value)) {
      imageModel.value = images.isNotEmpty ? images.first['id']! : '';
    }
  }

  void setMode(String m) => mode.value = m;

  Future<void> setProvider(String p) async {
    provider.value = p;
    await _hive.setSetting(AppConstants.keyVideoProvider, p);
    _ensureModelDefaults();
    await _hive.setSetting(AppConstants.keyVideoTextModel, textModel.value);
    await _hive.setSetting(AppConstants.keyVideoImageModel, imageModel.value);
  }

  /// Read-through helper used by the settings sheet to prefill fields.
  String? Function(String) get mapHive =>
      (key) => _hive.getSetting<String>(key);

  /// Persists the API key (and custom URL) for the currently selected provider.
  Future<void> saveProviderConfig({
    required String key,
    String customUrl = '',
  }) async {
    switch (provider.value) {
      case 'fal':
        await _hive.setSetting(AppConstants.keyFalKey, key);
        break;
      case 'custom':
        await _hive.setSetting(AppConstants.keyVideoCustomKey, key);
        await _hive.setSetting(AppConstants.keyVideoCustomBaseUrl, customUrl);
        break;
      default:
        await _hive.setSetting(AppConstants.keyReplicateKey, key);
    }
    // Nudge dependent observers (isConfigured is derived from the service).
    provider.refresh();
  }

  Future<void> setModel(String id) async {
    if (mode.value == 'image') {
      imageModel.value = id;
      await _hive.setSetting(AppConstants.keyVideoImageModel, id);
    } else {
      textModel.value = id;
      await _hive.setSetting(AppConstants.keyVideoTextModel, id);
    }
  }

  Future<void> setAspectRatio(String r) async {
    aspectRatio.value = r;
    await _hive.setSetting(AppConstants.keyVideoAspectRatio, r);
  }

  Future<void> setDuration(int d) async {
    duration.value = d;
    await _hive.setSetting(AppConstants.keyVideoDuration, d);
  }

  Future<void> pickImage({bool fromCamera = false}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1536,
      imageQuality: 92,
    );
    if (picked != null) {
      sourceImagePath.value = picked.path;
      if (mode.value != 'image') mode.value = 'image';
    }
  }

  void clearImage() => sourceImagePath.value = null;

  Future<void> generate() async {
    if (isGenerating.value) return;

    if (!isConfigured) {
      Get.snackbar('Setup needed',
          'Add a video API key in Settings → Video Generation.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (mode.value == 'text' && promptController.text.trim().isEmpty) {
      Get.snackbar('Prompt required', 'Describe the video you want to create.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (mode.value == 'image' && (sourceImagePath.value ?? '').isEmpty) {
      Get.snackbar('Image required', 'Pick a base image to animate.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final job = VideoJob(
      id: _uuid.v4(),
      prompt: promptController.text.trim(),
      mode: mode.value,
      sourceImagePath: mode.value == 'image' ? sourceImagePath.value : null,
      provider: provider.value,
      model: currentModel,
      aspectRatio: aspectRatio.value,
      durationSeconds: duration.value,
      status: 'generating',
    );

    isGenerating.value = true;
    statusDetail.value = 'Submitting…';
    activeJob.value = job;

    try {
      final path = await _service.generate(
        prompt: job.prompt,
        mode: job.mode,
        imagePath: job.sourceImagePath,
        model: job.model,
        aspectRatio: job.aspectRatio,
        durationSeconds: job.durationSeconds,
        onProgress: (d) => statusDetail.value = d,
      );
      final done = job.copyWith(status: 'completed', localPath: path);
      activeJob.value = done;
      await _service.saveJob(done);
      history.insert(0, done);
    } catch (e) {
      final msg = e is VideoGenException ? e.message : e.toString();
      final failed = job.copyWith(status: 'failed', error: msg);
      activeJob.value = failed;
      Get.snackbar('Generation failed', msg,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5));
    } finally {
      isGenerating.value = false;
      statusDetail.value = '';
    }
  }

  Future<void> deleteJob(VideoJob job) async {
    await _service.deleteJob(job);
    history.removeWhere((j) => j.id == job.id);
    if (activeJob.value?.id == job.id) activeJob.value = null;
  }

  void openJob(VideoJob job) {
    activeJob.value = job;
    if (job.prompt.isNotEmpty) promptController.text = job.prompt;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../models/video_job.dart';
import 'hive_service.dart';
import 'app_log_service.dart';

/// Thrown for user-actionable failures (missing key, provider error, timeout).
class VideoGenException implements Exception {
  final String message;
  VideoGenException(this.message);
  @override
  String toString() => message;
}

/// Generates videos from a text prompt or a base image via a cloud provider.
///
/// Providers implement an async "submit job → poll status → download result"
/// flow. Currently supported: Replicate, Fal.ai, and a generic Custom endpoint.
/// The service is provider-agnostic to the caller: [generate] returns a
/// [VideoJob] with a local .mp4 path on success.
class VideoGenService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();
  AppLogService get _log => Get.find<AppLogService>();

  static const Duration _pollInterval = Duration(seconds: 3);
  static const Duration _maxWait = Duration(minutes: 8);

  String get provider =>
      _hive.getSetting(AppConstants.keyVideoProvider,
          defaultValue: AppConstants.defaultVideoProvider) ??
      AppConstants.defaultVideoProvider;

  String apiKeyFor(String p) {
    switch (p) {
      case 'fal':
        return _hive.getSetting(AppConstants.keyFalKey) ?? '';
      case 'custom':
        return _hive.getSetting(AppConstants.keyVideoCustomKey) ?? '';
      default:
        return _hive.getSetting(AppConstants.keyReplicateKey) ?? '';
    }
  }

  bool get isConfigured {
    if (provider == 'custom') {
      final base = _hive.getSetting(AppConstants.keyVideoCustomBaseUrl) ?? '';
      return (base as String).isNotEmpty;
    }
    return apiKeyFor(provider).isNotEmpty;
  }

  /// Runs a full generation. [onProgress] receives human-readable status lines.
  /// Throws [VideoGenException] on failure. Returns the local .mp4 path.
  Future<String> generate({
    required String prompt,
    required String mode, // 'text' | 'image'
    String? imagePath,
    required String model,
    required String aspectRatio,
    required int durationSeconds,
    void Function(String detail)? onProgress,
  }) async {
    final p = provider;
    if (!isConfigured) {
      throw VideoGenException(
          'No API key set for ${p.toUpperCase()}. Add it in Settings → Video Generation.');
    }
    if (mode == 'image' && (imagePath == null || imagePath.isEmpty)) {
      throw VideoGenException('Pick a base image first.');
    }
    if (mode == 'text' && prompt.trim().isEmpty) {
      throw VideoGenException('Enter a prompt to describe your video.');
    }

    _log.info('[Video] generate start',
        details: {'provider': p, 'mode': mode, 'model': model});
    onProgress?.call('Submitting to ${p.toUpperCase()}…');

    String? imageDataUri;
    if (mode == 'image' && imagePath != null) {
      imageDataUri = await _encodeImage(imagePath);
    }

    final String remoteUrl;
    switch (p) {
      case 'fal':
        remoteUrl = await _runFal(
          prompt: prompt,
          model: model,
          imageDataUri: imageDataUri,
          aspectRatio: aspectRatio,
          durationSeconds: durationSeconds,
          onProgress: onProgress,
        );
        break;
      case 'custom':
        remoteUrl = await _runCustom(
          prompt: prompt,
          imageDataUri: imageDataUri,
          aspectRatio: aspectRatio,
          durationSeconds: durationSeconds,
          onProgress: onProgress,
        );
        break;
      default:
        remoteUrl = await _runReplicate(
          prompt: prompt,
          model: model,
          imageDataUri: imageDataUri,
          aspectRatio: aspectRatio,
          durationSeconds: durationSeconds,
          onProgress: onProgress,
        );
    }

    onProgress?.call('Downloading video…');
    final path = await _download(remoteUrl);
    _log.info('[Video] saved', details: path);
    return path;
  }

  // ─── Replicate ──────────────────────────────────────────────
  // Uses the model-name prediction endpoint so no version pinning is needed:
  //   POST /v1/models/{owner}/{name}/predictions  { "input": {...} }
  // then polls GET /v1/predictions/{id} until succeeded/failed/canceled.
  Future<String> _runReplicate({
    required String prompt,
    required String model,
    String? imageDataUri,
    required String aspectRatio,
    required int durationSeconds,
    void Function(String)? onProgress,
  }) async {
    final key = apiKeyFor('replicate');
    final headers = {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'Prefer': 'wait=1',
    };

    final input = <String, dynamic>{
      'prompt': prompt,
      'aspect_ratio': aspectRatio,
      'duration': durationSeconds,
    };
    if (imageDataUri != null) {
      // Different models use different keys; send the common aliases.
      input['image'] = imageDataUri;
      input['first_frame_image'] = imageDataUri;
      input['input_image'] = imageDataUri;
    }

    final createUri =
        Uri.parse('${AppConstants.replicateEndpoint}/models/$model/predictions');
    final createResp = await http
        .post(createUri, headers: headers, body: jsonEncode({'input': input}))
        .timeout(const Duration(seconds: 60));

    if (createResp.statusCode != 200 && createResp.statusCode != 201) {
      throw VideoGenException(
          'Replicate error (${createResp.statusCode}): ${_briefError(createResp.body)}');
    }

    var body = jsonDecode(createResp.body) as Map<String, dynamic>;
    var status = body['status'] as String? ?? 'starting';
    final getUrl = (body['urls']?['get'] as String?) ??
        '${AppConstants.replicateEndpoint}/predictions/${body['id']}';

    final deadline = DateTime.now().add(_maxWait);
    while (status != 'succeeded' &&
        status != 'failed' &&
        status != 'canceled') {
      if (DateTime.now().isAfter(deadline)) {
        throw VideoGenException('Timed out waiting for Replicate to render.');
      }
      onProgress?.call(_progressLabel(status));
      await Future.delayed(_pollInterval);
      final poll = await http
          .get(Uri.parse(getUrl), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (poll.statusCode != 200) {
        throw VideoGenException(
            'Replicate poll failed (${poll.statusCode}).');
      }
      body = jsonDecode(poll.body) as Map<String, dynamic>;
      status = body['status'] as String? ?? status;
    }

    if (status != 'succeeded') {
      throw VideoGenException(
          'Generation $status: ${_briefError(body['error']?.toString() ?? '')}');
    }

    final url = _extractUrl(body['output']);
    if (url == null) {
      throw VideoGenException('Replicate returned no video URL.');
    }
    return url;
  }

  // ─── Fal.ai ─────────────────────────────────────────────────
  // POST https://queue.fal.run/{model}  → { request_id, status_url, response_url }
  // Poll status_url until COMPLETED, then GET response_url → { video: { url } }.
  Future<String> _runFal({
    required String prompt,
    required String model,
    String? imageDataUri,
    required String aspectRatio,
    required int durationSeconds,
    void Function(String)? onProgress,
  }) async {
    final key = apiKeyFor('fal');
    final headers = {
      'Authorization': 'Key $key',
      'Content-Type': 'application/json',
    };

    final payload = <String, dynamic>{
      'prompt': prompt,
      'aspect_ratio': aspectRatio,
      'duration': durationSeconds,
    };
    if (imageDataUri != null) {
      payload['image_url'] = imageDataUri;
    }

    final submitUri = Uri.parse('${AppConstants.falQueueEndpoint}/$model');
    final submit = await http
        .post(submitUri, headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 60));
    if (submit.statusCode != 200 && submit.statusCode != 201) {
      throw VideoGenException(
          'Fal error (${submit.statusCode}): ${_briefError(submit.body)}');
    }
    final queued = jsonDecode(submit.body) as Map<String, dynamic>;
    final statusUrl = queued['status_url'] as String?;
    final responseUrl = queued['response_url'] as String?;
    if (statusUrl == null || responseUrl == null) {
      throw VideoGenException('Fal did not return a job URL.');
    }

    final deadline = DateTime.now().add(_maxWait);
    var status = 'IN_QUEUE';
    while (status != 'COMPLETED') {
      if (DateTime.now().isAfter(deadline)) {
        throw VideoGenException('Timed out waiting for Fal to render.');
      }
      onProgress?.call(_progressLabel(status));
      await Future.delayed(_pollInterval);
      final poll = await http
          .get(Uri.parse(statusUrl), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (poll.statusCode != 200) {
        throw VideoGenException('Fal poll failed (${poll.statusCode}).');
      }
      final pb = jsonDecode(poll.body) as Map<String, dynamic>;
      status = pb['status'] as String? ?? status;
      if (status == 'FAILED' || status == 'ERROR') {
        throw VideoGenException('Fal generation failed.');
      }
    }

    final result = await http
        .get(Uri.parse(responseUrl), headers: headers)
        .timeout(const Duration(seconds: 30));
    if (result.statusCode != 200) {
      throw VideoGenException(
          'Fal result fetch failed (${result.statusCode}).');
    }
    final rb = jsonDecode(result.body) as Map<String, dynamic>;
    final url = _extractUrl(rb['video'] ?? rb['output'] ?? rb['url']);
    if (url == null) {
      throw VideoGenException('Fal returned no video URL.');
    }
    return url;
  }

  // ─── Custom endpoint ────────────────────────────────────────
  // Minimal contract: POST {baseUrl} with { prompt, image, aspect_ratio,
  // duration } and either return a video URL directly (sync) or a job with a
  // status/poll URL. We handle the common synchronous case and simple polling.
  Future<String> _runCustom({
    required String prompt,
    String? imageDataUri,
    required String aspectRatio,
    required int durationSeconds,
    void Function(String)? onProgress,
  }) async {
    final base = _hive.getSetting(AppConstants.keyVideoCustomBaseUrl) ?? '';
    final key = apiKeyFor('custom');
    if ((base as String).isEmpty) {
      throw VideoGenException('Set a Custom endpoint URL in Settings.');
    }
    final headers = {
      'Content-Type': 'application/json',
      if (key.isNotEmpty) 'Authorization': 'Bearer $key',
    };
    final payload = <String, dynamic>{
      'prompt': prompt,
      'aspect_ratio': aspectRatio,
      'duration': durationSeconds,
      if (imageDataUri != null) 'image': imageDataUri,
    };

    final resp = await http
        .post(Uri.parse(base), headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 120));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw VideoGenException(
          'Custom endpoint error (${resp.statusCode}): ${_briefError(resp.body)}');
    }
    final decoded = jsonDecode(resp.body);
    // Direct URL forms
    final direct = _extractUrl(decoded is Map
        ? (decoded['video'] ?? decoded['output'] ?? decoded['url'])
        : decoded);
    if (direct != null) return direct;

    // Simple poll form: { status_url } or { poll_url }
    if (decoded is Map) {
      final pollUrl = decoded['status_url'] ?? decoded['poll_url'];
      if (pollUrl is String) {
        final deadline = DateTime.now().add(_maxWait);
        while (DateTime.now().isBefore(deadline)) {
          onProgress?.call('Rendering…');
          await Future.delayed(_pollInterval);
          final poll = await http
              .get(Uri.parse(pollUrl), headers: headers)
              .timeout(const Duration(seconds: 30));
          if (poll.statusCode == 200) {
            final pb = jsonDecode(poll.body);
            final url = _extractUrl(pb is Map
                ? (pb['video'] ?? pb['output'] ?? pb['url'])
                : pb);
            if (url != null) return url;
          }
        }
        throw VideoGenException('Custom endpoint timed out.');
      }
    }
    throw VideoGenException('Custom endpoint returned no video URL.');
  }

  // ─── Helpers ────────────────────────────────────────────────

  Future<String> _encodeImage(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw VideoGenException('Selected image no longer exists.');
    }
    final bytes = await file.readAsBytes();
    final ext = path.split('.').last.toLowerCase();
    final mime = (ext == 'png')
        ? 'image/png'
        : (ext == 'webp')
            ? 'image/webp'
            : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  /// Recursively pull the first http(s) URL out of a String / List / Map.
  String? _extractUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return value.startsWith('http') ? value : null;
    }
    if (value is List) {
      for (final item in value) {
        final found = _extractUrl(item);
        if (found != null) return found;
      }
      return null;
    }
    if (value is Map) {
      // Prefer a `url` field, else scan values.
      final direct = _extractUrl(value['url']);
      if (direct != null) return direct;
      for (final v in value.values) {
        final found = _extractUrl(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<String> _download(String url) async {
    final resp =
        await http.get(Uri.parse(url)).timeout(const Duration(minutes: 3));
    if (resp.statusCode != 200) {
      throw VideoGenException('Failed to download video (${resp.statusCode}).');
    }
    final dir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${dir.path}/videos');
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }
    final name = 'vid_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final file = File('${videoDir.path}/$name');
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }

  String _progressLabel(String status) {
    switch (status.toLowerCase()) {
      case 'starting':
      case 'in_queue':
        return 'Queued…';
      case 'processing':
      case 'in_progress':
        return 'Rendering frames…';
      default:
        return 'Working…';
    }
  }

  String _briefError(String body) {
    if (body.isEmpty) return 'no details';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return (decoded['detail'] ??
                decoded['error'] ??
                decoded['message'] ??
                body)
            .toString();
      }
    } catch (_) {}
    return body.length > 180 ? '${body.substring(0, 180)}…' : body;
  }

  // ─── History persistence ────────────────────────────────────

  List<VideoJob> loadHistory() {
    final raw = _hive.videoJobsBox.values
        .whereType<Map>()
        .map((m) => VideoJob.fromMap(m))
        .toList();
    raw.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return raw;
  }

  Future<void> saveJob(VideoJob job) async {
    await _hive.videoJobsBox.put(job.id, job.toMap());
  }

  Future<void> deleteJob(VideoJob job) async {
    await _hive.videoJobsBox.delete(job.id);
    if (job.localPath != null) {
      try {
        final f = File(job.localPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

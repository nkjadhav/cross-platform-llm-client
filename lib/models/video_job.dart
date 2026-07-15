/// Represents a single video generation request and its result.
///
/// A job moves through: queued → generating → completed | failed.
/// When completed, [localPath] points to the downloaded .mp4 on disk and
/// [remoteUrl] holds the provider URL it was fetched from.
class VideoJob {
  final String id;
  final String prompt;

  /// 'text' for text-to-video, 'image' for image-to-video.
  final String mode;

  /// Absolute path to the source image used for image-to-video (nullable).
  final String? sourceImagePath;

  final String provider;
  final String model;
  final String aspectRatio;
  final int durationSeconds;

  /// 'queued', 'generating', 'completed', 'failed'.
  final String status;

  /// Free-text progress line shown while generating (e.g. "Rendering frames…").
  final String statusDetail;

  final String? remoteUrl;
  final String? localPath;
  final String? error;
  final DateTime createdAt;

  VideoJob({
    required this.id,
    required this.prompt,
    required this.mode,
    this.sourceImagePath,
    required this.provider,
    required this.model,
    required this.aspectRatio,
    required this.durationSeconds,
    this.status = 'queued',
    this.statusDetail = '',
    this.remoteUrl,
    this.localPath,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  VideoJob copyWith({
    String? status,
    String? statusDetail,
    String? remoteUrl,
    String? localPath,
    String? error,
  }) =>
      VideoJob(
        id: id,
        prompt: prompt,
        mode: mode,
        sourceImagePath: sourceImagePath,
        provider: provider,
        model: model,
        aspectRatio: aspectRatio,
        durationSeconds: durationSeconds,
        status: status ?? this.status,
        statusDetail: statusDetail ?? this.statusDetail,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        localPath: localPath ?? this.localPath,
        error: error ?? this.error,
        createdAt: createdAt,
      );

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isActive => status == 'queued' || status == 'generating';

  Map<String, dynamic> toMap() => {
        'id': id,
        'prompt': prompt,
        'mode': mode,
        'sourceImagePath': sourceImagePath,
        'provider': provider,
        'model': model,
        'aspectRatio': aspectRatio,
        'durationSeconds': durationSeconds,
        'status': status,
        'statusDetail': statusDetail,
        'remoteUrl': remoteUrl,
        'localPath': localPath,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VideoJob.fromMap(Map<dynamic, dynamic> map) => VideoJob(
        id: map['id'] ?? '',
        prompt: map['prompt'] ?? '',
        mode: map['mode'] ?? 'text',
        sourceImagePath: map['sourceImagePath'],
        provider: map['provider'] ?? '',
        model: map['model'] ?? '',
        aspectRatio: map['aspectRatio'] ?? '16:9',
        durationSeconds: map['durationSeconds'] ?? 5,
        status: map['status'] ?? 'queued',
        statusDetail: map['statusDetail'] ?? '',
        remoteUrl: map['remoteUrl'],
        localPath: map['localPath'],
        error: map['error'],
        createdAt:
            DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      );
}

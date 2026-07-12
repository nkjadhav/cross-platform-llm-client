import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import '../controllers/video_gen_controller.dart';
import '../core/constants.dart';
import '../models/video_job.dart';
import '../widgets/video_player_card.dart';

class VideoGenView extends StatelessWidget {
  const VideoGenView({super.key});

  Color _accent(bool dark) =>
      dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final c = Get.find<VideoGenController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(isDark);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Column(
          children: [
            _header(context, isDark, accent, c),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _modeToggle(context, isDark, accent, c),
                  const SizedBox(height: 16),
                  Obx(() => c.mode.value == 'image'
                      ? _imagePicker(context, isDark, accent, c)
                      : const SizedBox.shrink()),
                  Obx(() => c.mode.value == 'image'
                      ? const SizedBox(height: 16)
                      : const SizedBox.shrink()),
                  _promptField(context, isDark, accent, c),
                  const SizedBox(height: 16),
                  _controls(context, isDark, accent, c),
                  const SizedBox(height: 20),
                  Obx(() {
                    // provider.refresh() fires after a key is saved, so this
                    // re-evaluates the (non-reactive) service config state.
                    c.provider.value;
                    if (c.isConfigured) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _configBanner(context, isDark, accent, c),
                    );
                  }),
                  _generateButton(context, isDark, accent, c),
                  const SizedBox(height: 24),
                  _resultArea(context, isDark, accent, c),
                  const SizedBox(height: 24),
                  _historySection(context, isDark, accent, c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────
  Widget _header(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF5856D6), Color(0xFF0A84FF)]),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.movie_creation_rounded,
                color: Colors.white, size: 19),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Video Studio',
                  style: GoogleFonts.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black)),
              Text('Generate videos from text or images',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Theme.of(context).hintColor)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.tune_rounded,
                color: isDark ? Colors.white70 : Colors.black54),
            onPressed: () => _showProviderSheet(context, isDark, accent, c),
          ),
        ],
      ),
    );
  }

  // ─── Mode toggle ─────────────────────────────────────────────
  Widget _modeToggle(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    Widget seg(String value, String label, IconData icon) {
      return Expanded(
        child: Obx(() {
          final sel = c.mode.value == value;
          return GestureDetector(
            onTap: () => c.setMode(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: sel ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 17,
                      color: sel
                          ? Colors.white
                          : (isDark ? Colors.white60 : Colors.black54)),
                  const SizedBox(width: 7),
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? Colors.white
                              : (isDark ? Colors.white60 : Colors.black54))),
                ],
              ),
            ),
          );
        }),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(children: [
        seg('text', 'Text → Video', Icons.text_fields_rounded),
        seg('image', 'Image → Video', Icons.image_rounded),
      ]),
    );
  }

  // ─── Image picker ────────────────────────────────────────────
  Widget _imagePicker(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return Obx(() {
      final path = c.sourceImagePath.value;
      if (path != null && path.isNotEmpty) {
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(File(path),
                  width: double.infinity, height: 220, fit: BoxFit.cover),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(children: [
                _roundBtn(Icons.refresh_rounded, () => c.pickImage(),
                    tooltip: 'Change'),
                const SizedBox(width: 8),
                _roundBtn(Icons.close_rounded, c.clearImage, tooltip: 'Remove'),
              ]),
            ),
          ],
        );
      }
      return GestureDetector(
        onTap: () => _showImageSourceSheet(context, isDark, c),
        child: DottedBorderBox(
          isDark: isDark,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 40, color: accent),
              const SizedBox(height: 10),
              Text('Add a base image',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 3),
              Text('Tap to choose from gallery or camera',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: Theme.of(context).hintColor)),
            ],
          ),
        ),
      );
    });
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap, {String? tooltip}) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }

  // ─── Prompt field ────────────────────────────────────────────
  Widget _promptField(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: c.promptController,
        minLines: 3,
        maxLines: 6,
        style: GoogleFonts.inter(
            fontSize: 15, color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: c.mode.value == 'image'
              ? 'Describe the motion (optional) — e.g. "slow zoom, gentle wind"'
              : 'Describe your video — e.g. "a neon city at night, cinematic, rain"',
          hintStyle: GoogleFonts.inter(
              fontSize: 14.5, color: Theme.of(context).hintColor),
        ),
      ),
    );
  }

  // ─── Controls ────────────────────────────────────────────────
  Widget _controls(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _controlLabel(context, 'Aspect Ratio'),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 8,
              children: AppConstants.videoAspectRatios
                  .map((r) => _chip(
                        label: r,
                        selected: c.aspectRatio.value == r,
                        accent: accent,
                        isDark: isDark,
                        onTap: () => c.setAspectRatio(r),
                      ))
                  .toList(),
            )),
        const SizedBox(height: 16),
        _controlLabel(context, 'Duration'),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 8,
              children: AppConstants.videoDurations
                  .map((d) => _chip(
                        label: '${d}s',
                        selected: c.duration.value == d,
                        accent: accent,
                        isDark: isDark,
                        onTap: () => c.setDuration(d),
                      ))
                  .toList(),
            )),
        const SizedBox(height: 16),
        _controlLabel(context, 'Model'),
        const SizedBox(height: 8),
        _modelDropdown(context, isDark, accent, c),
      ],
    );
  }

  Widget _controlLabel(BuildContext context, String text) => Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: Theme.of(context).hintColor),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required Color accent,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? accent
              : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? accent
                : (isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA)),
          ),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87))),
      ),
    );
  }

  Widget _modelDropdown(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return Obx(() {
      final models = c.modelsForMode;
      final current = c.currentModel;
      if (models.isEmpty) {
        return Text('No models for this provider',
            style: GoogleFonts.inter(
                fontSize: 13, color: Theme.of(context).hintColor));
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: models.any((m) => m['id'] == current)
                ? current
                : models.first['id'],
            icon: Icon(Icons.expand_more_rounded,
                color: isDark ? Colors.white54 : Colors.black45),
            dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            items: models
                .map((m) => DropdownMenuItem<String>(
                      value: m['id'],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(m['name'] ?? m['id']!,
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDark ? Colors.white : Colors.black)),
                          if ((m['desc'] ?? '').isNotEmpty)
                            Text(m['desc']!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: Theme.of(context).hintColor)),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) c.setModel(v);
            },
          ),
        ),
      );
    });
  }

  Widget _configBanner(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return GestureDetector(
      onTap: () => _showProviderSheet(context, isDark, accent, c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9500).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFFFF9500).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.key_rounded, color: Color(0xFFFF9500), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Add a video API key to start generating. Tap to set it up.',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: isDark ? Colors.white54 : Colors.black45, size: 20),
          ],
        ),
      ),
    );
  }

  // ─── Generate button ─────────────────────────────────────────
  Widget _generateButton(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return Obx(() {
      final busy = c.isGenerating.value;
      return SizedBox(
        width: double.infinity,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: busy
                ? null
                : const LinearGradient(
                    colors: [Color(0xFF5856D6), Color(0xFF0A84FF)]),
            color: busy ? (isDark ? const Color(0xFF1C1C1E) : Colors.white) : null,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: busy ? null : c.generate,
              child: Center(
                child: busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: accent),
                          ),
                          const SizedBox(width: 12),
                          Obx(() => Text(
                                c.statusDetail.value.isEmpty
                                    ? 'Generating…'
                                    : c.statusDetail.value,
                                style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black)),
                              )),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Text('Generate Video',
                              style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    });
  }

  // ─── Result area ─────────────────────────────────────────────
  Widget _resultArea(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return Obx(() {
      final job = c.activeJob.value;
      if (job == null) return const SizedBox.shrink();

      if (job.status == 'generating') {
        return _placeholderCard(
          context,
          isDark,
          icon: Icons.hourglass_top_rounded,
          title: 'Creating your video',
          subtitle: c.statusDetail.value.isEmpty
              ? 'This can take up to a couple of minutes.'
              : c.statusDetail.value,
          showSpinner: true,
          accent: accent,
        );
      }

      if (job.status == 'failed') {
        return _placeholderCard(
          context,
          isDark,
          icon: Icons.error_outline_rounded,
          title: 'Generation failed',
          subtitle: job.error ?? 'Something went wrong.',
          color: const Color(0xFFFF3B30),
          accent: accent,
        );
      }

      if (job.isCompleted && job.localPath != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _controlLabel(context, 'Result'),
            const SizedBox(height: 8),
            VideoPlayerCard(
                path: job.localPath!, aspectRatio: job.aspectRatio),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _actionButton(
                  isDark: isDark,
                  icon: Icons.download_rounded,
                  label: 'Save',
                  onTap: () => _saveToGallery(job.localPath!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  isDark: isDark,
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  onTap: () => _shareVideo(job.localPath!),
                ),
              ),
            ]),
          ],
        );
      }
      return const SizedBox.shrink();
    });
  }

  Widget _placeholderCard(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    Color? color,
    bool showSpinner = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (showSpinner)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
            )
          else
            Icon(icon, size: 38, color: color ?? accent),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }

  Widget _actionButton({
    required bool isDark,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: isDark ? Colors.white : Colors.black),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── History ─────────────────────────────────────────────────
  Widget _historySection(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    return Obx(() {
      final items = c.history;
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _controlLabel(context, 'History'),
          const SizedBox(height: 10),
          ...items.map((j) => _historyTile(context, isDark, accent, c, j)),
        ],
      );
    });
  }

  Widget _historyTile(BuildContext context, bool isDark, Color accent,
      VideoGenController c, VideoJob job) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => c.openJob(job),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                      job.mode == 'image'
                          ? Icons.image_rounded
                          : Icons.text_fields_rounded,
                      color: accent,
                      size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.prompt.isEmpty
                            ? '(image → video)'
                            : job.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${job.aspectRatio} · ${job.durationSeconds}s · ${job.provider}',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 20, color: isDark ? Colors.white38 : Colors.black38),
                  onPressed: () => c.deleteJob(job),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────
  Future<void> _saveToGallery(String path) async {
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }
      await Gal.putVideo(path);
      Get.snackbar('Saved', 'Video saved to your gallery.',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Save failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _shareVideo(String path) async {
    try {
      await Share.shareXFiles([XFile(path)], text: 'Made with Video Studio');
    } catch (e) {
      Get.snackbar('Share failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ─── Image source sheet ──────────────────────────────────────
  void _showImageSourceSheet(
      BuildContext context, bool isDark, VideoGenController c) {
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Get.back();
                  c.pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a Photo'),
                onTap: () {
                  Get.back();
                  c.pickImage(fromCamera: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Provider configuration sheet ────────────────────────────
  void _showProviderSheet(BuildContext context, bool isDark, Color accent,
      VideoGenController c) {
    final providers = [
      {'id': 'replicate', 'name': 'Replicate', 'hint': 'r8_...'},
      {'id': 'fal', 'name': 'Fal.ai', 'hint': 'Key id:secret'},
      {'id': 'custom', 'name': 'Custom Endpoint', 'hint': 'API key (optional)'},
    ];
    final keyController = TextEditingController();
    final urlController = TextEditingController();

    void loadFields(String p) {
      final hive = c.mapHive;
      switch (p) {
        case 'fal':
          keyController.text = hive(AppConstants.keyFalKey) ?? '';
          break;
        case 'custom':
          keyController.text = hive(AppConstants.keyVideoCustomKey) ?? '';
          urlController.text = hive(AppConstants.keyVideoCustomBaseUrl) ?? '';
          break;
        default:
          keyController.text = hive(AppConstants.keyReplicateKey) ?? '';
      }
    }

    loadFields(c.provider.value);

    Get.bottomSheet(
      Obx(() {
        final p = c.provider.value;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Video Provider',
                  style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 4),
              Text('Choose a service and paste your API key.',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Theme.of(context).hintColor)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: providers.map((pr) {
                  final sel = p == pr['id'];
                  return _chip(
                    label: pr['name']!,
                    selected: sel,
                    accent: accent,
                    isDark: isDark,
                    onTap: () {
                      c.setProvider(pr['id']!);
                      loadFields(pr['id']!);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              if (p == 'custom') ...[
                _sheetField(isDark, urlController, 'Endpoint URL',
                    'https://your-endpoint/generate'),
                const SizedBox(height: 12),
              ],
              _sheetField(
                isDark,
                keyController,
                'API Key',
                providers.firstWhere((e) => e['id'] == p)['hint']!,
                obscure: true,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await c.saveProviderConfig(
                      key: keyController.text.trim(),
                      customUrl: urlController.text.trim(),
                    );
                    Get.back();
                    Get.snackbar('Saved', 'Video provider updated.',
                        snackPosition: SnackPosition.BOTTOM);
                  },
                  child: Text('Save',
                      style: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 6),
              _providerHelp(context, p),
            ],
          ),
        );
      }),
      isScrollControlled: true,
    );
  }

  Widget _providerHelp(BuildContext context, String provider) {
    String text;
    switch (provider) {
      case 'fal':
        text = 'Get a key at fal.ai/dashboard/keys.';
        break;
      case 'custom':
        text =
            'Your endpoint should accept POST { prompt, image, aspect_ratio, duration } and return a video URL.';
        break;
      default:
        text = 'Get a token at replicate.com/account/api-tokens.';
    }
    return Text(text,
        style: GoogleFonts.inter(
            fontSize: 12, color: Theme.of(context).hintColor));
  }

  Widget _sheetField(
      bool isDark, TextEditingController controller, String label, String hint,
      {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: isDark ? Colors.white54 : Colors.black45)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: GoogleFonts.inter(
              fontSize: 14, color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// A dashed-border container used as the empty image drop target.
class DottedBorderBox extends StatelessWidget {
  final bool isDark;
  final Widget child;
  const DottedBorderBox({super.key, required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
          width: 1.4,
        ),
      ),
      child: child,
    );
  }
}

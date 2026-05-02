import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';

enum _ComposeMediaType { photo, video }

class PostComposeSheet extends ConsumerStatefulWidget {
  const PostComposeSheet({super.key});

  @override
  ConsumerState<PostComposeSheet> createState() => _PostComposeSheetState();
}

class _PostComposeSheetState extends ConsumerState<PostComposeSheet> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  _ComposeMediaType _mediaType = _ComposeMediaType.photo;
  Uint8List? _imageBytes;
  Uint8List? _videoBytes;
  String? _videoName;
  String _videoMimeType = 'video/mp4';
  bool _submitting = false;
  double _uploadProgress = 0;
  String _uploadLabel = '';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 72,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사진은 15MB 이하로 선택해주세요')));
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _mediaType = _ComposeMediaType.photo;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('이미지 선택 실패: $e')));
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null) return;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이 영상은 브라우저에서 읽을 수 없습니다')));
        return;
      }
      if (bytes.length > 120 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('영상은 120MB 이하로 선택해주세요')));
        return;
      }
      setState(() {
        _videoBytes = bytes;
        _videoName = file.name;
        _videoMimeType = _mimeFromExtension(file.extension ?? '');
        _mediaType = _ComposeMediaType.video;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('영상 선택 실패: $e')));
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제목을 입력해주세요')));
      return;
    }
    if (_mediaType == _ComposeMediaType.photo && _imageBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('업로드할 사진을 선택해주세요')));
      return;
    }
    if (_mediaType == _ComposeMediaType.video && _videoBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('업로드할 영상을 선택해주세요')));
      return;
    }

    String? createdPostId;
    setState(() {
      _submitting = true;
      _uploadProgress = 0;
      _uploadLabel = '업로드 준비 중';
    });
    try {
      final content = _contentCtrl.text.trim().isEmpty
          ? null
          : _contentCtrl.text.trim();
      if (_mediaType == _ComposeMediaType.video) {
        final postId = await FirebaseService.createPost(
          title: title,
          content: content,
          mediaType: 'video',
          videoStatus: 'uploading',
          videoTrimStartSec: 0,
          videoTrimEndSec: 12,
        );
        createdPostId = postId;
        final sourcePath = await FirebaseService.uploadPostVideoSource(
          _videoBytes!,
          postId: postId,
          trimStartSec: 0,
          trimEndSec: 12,
          contentType: _videoMimeType,
          extension: _extensionFromName(_videoName ?? ''),
          onProgress: (progress) =>
              _setUploadProgress('영상 ${_percent(progress)}% 업로드 중', progress),
        );
        if (sourcePath == null) throw Exception('영상 업로드 권한이 없습니다');
        final sourceUrl = await FirebaseService.getStorageDownloadUrl(
          sourcePath,
        );
        _setUploadProgress('영상 처리 요청 중', 1);
        await FirebaseService.markPostVideoProcessing(
          postId,
          sourcePath: sourcePath,
          sourceUrl: sourceUrl,
        );
      } else {
        String? imageUrl;
        if (_imageBytes != null) {
          imageUrl = await FirebaseService.uploadPostImage(
            _imageBytes!,
            onProgress: (progress) =>
                _setUploadProgress('사진 ${_percent(progress)}% 업로드 중', progress),
          );
        }
        _setUploadProgress('게시물 저장 중', 1);
        await FirebaseService.createPost(
          title: title,
          content: content,
          imageUrl: imageUrl,
          mediaType: 'photo',
        );
      }
      ref.invalidate(postsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (createdPostId != null) {
        await FirebaseService.deletePost(createdPostId);
      }
      setState(() => _submitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('등록 실패: $e')));
    }
  }

  String _extensionFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'mp4';
    return name.substring(dot + 1).toLowerCase();
  }

  String _mimeFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      case 'mp4':
      default:
        return 'video/mp4';
    }
  }

  int _percent(double progress) => (progress * 100).clamp(0, 100).round();

  void _setUploadProgress(String label, double progress) {
    if (!mounted) return;
    setState(() {
      _uploadLabel = label;
      _uploadProgress = progress.clamp(0, 1).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.subtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _ComposeHeader(submitting: _submitting, onSubmit: _submit),
              const SizedBox(height: 18),
              _MediaTypeSwitch(
                selected: _mediaType,
                enabled: !_submitting,
                onChanged: (value) => setState(() => _mediaType = value),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _mediaType == _ComposeMediaType.photo
                    ? _PhotoPicker(
                        key: const ValueKey('photo-picker'),
                        imageBytes: _imageBytes,
                        submitting: _submitting,
                        onPick: _pickImage,
                        onClear: () => setState(() => _imageBytes = null),
                      )
                    : _VideoPicker(
                        key: const ValueKey('video-picker'),
                        videoName: _videoName,
                        videoBytes: _videoBytes,
                        submitting: _submitting,
                        onPick: _pickVideo,
                        onClear: () => setState(() {
                          _videoBytes = null;
                          _videoName = null;
                          _videoMimeType = 'video/mp4';
                        }),
                      ),
              ),
              if (_submitting) ...[
                const SizedBox(height: 14),
                _UploadProgressPanel(
                  label: _uploadLabel,
                  progress: _uploadProgress,
                ),
              ],
              const SizedBox(height: 16),
              _StyledTextField(
                controller: _titleCtrl,
                maxLength: 60,
                hintText: _mediaType == _ComposeMediaType.photo
                    ? '사진 제목'
                    : '영상 제목',
                icon: Icons.title_rounded,
              ),
              const SizedBox(height: 10),
              _StyledTextField(
                controller: _contentCtrl,
                maxLines: 4,
                hintText: _mediaType == _ComposeMediaType.photo
                    ? '사진 설명이나 재미있는 한마디'
                    : '영상 설명이나 재미있는 한마디',
                icon: Icons.short_text_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposeHeader extends StatelessWidget {
  final bool submitting;
  final VoidCallback onSubmit;

  const _ComposeHeader({required this.submitting, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.add_comment_rounded,
            color: Colors.white,
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('게시물 올리기', style: AppText.headline(21)),
              const SizedBox(height: 2),
              Text(
                '사진과 짧은 순간을 함께 나눠요',
                style: AppText.body(12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: submitting ? null : onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(62, 40),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          child: submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  '등록',
                  style: AppText.body(
                    14,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
        ),
      ],
    );
  }
}

class _UploadProgressPanel extends StatelessWidget {
  final String label;
  final double progress;

  const _UploadProgressPanel({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.isEmpty ? '업로드 중' : label,
                  style: AppText.body(
                    12,
                    weight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: AppText.body(
                  12,
                  weight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress <= 0 ? null : progress,
              backgroundColor: Colors.white.withValues(alpha: 0.7),
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTypeSwitch extends StatelessWidget {
  final _ComposeMediaType selected;
  final bool enabled;
  final ValueChanged<_ComposeMediaType> onChanged;

  const _MediaTypeSwitch({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MediaTypeButton(
              label: '사진',
              icon: Icons.photo_camera_outlined,
              selected: selected == _ComposeMediaType.photo,
              enabled: enabled,
              onTap: () => onChanged(_ComposeMediaType.photo),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _MediaTypeButton(
              label: '12초 영상',
              icon: Icons.movie_creation_outlined,
              selected: selected == _ComposeMediaType.video,
              enabled: enabled,
              onTap: () => onChanged(_ComposeMediaType.video),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _MediaTypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppText.body(
                  13,
                  weight: FontWeight.w800,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final Uint8List? imageBytes;
  final bool submitting;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _PhotoPicker({
    super.key,
    required this.imageBytes,
    required this.submitting,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: submitting ? null : onPick,
      child: AspectRatio(
        aspectRatio: 1.16,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: imageBytes != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(imageBytes!, fit: BoxFit.cover),
                    _ClearButton(onTap: onClear),
                  ],
                )
              : const Center(
                  child: _PickerEmptyState(
                    icon: Icons.add_photo_alternate_outlined,
                    title: '사진 추가',
                    subtitle: '갤러리에서 재미있는 순간을 골라주세요',
                  ),
                ),
        ),
      ),
    );
  }
}

class _VideoPicker extends StatelessWidget {
  final String? videoName;
  final Uint8List? videoBytes;
  final bool submitting;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _VideoPicker({
    super.key,
    required this.videoName,
    required this.videoBytes,
    required this.submitting,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasVideo = videoBytes != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: submitting ? null : onPick,
          child: Container(
            height: 174,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasVideo
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.border.withValues(alpha: 0.45),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: hasVideo
                    ? const [Color(0xFF061B33), Color(0xFF0A315F)]
                    : [
                        AppColors.primary.withValues(alpha: 0.045),
                        AppColors.secondary.withValues(alpha: 0.08),
                      ],
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Center(
                  child: hasVideo
                      ? _SelectedVideoState(videoName: videoName)
                      : const _PickerEmptyState(
                          icon: Icons.video_library_outlined,
                          title: '12초 이하 영상 선택',
                          subtitle: '긴 영상은 휴대폰에서 먼저 잘라서 올려주세요',
                        ),
                ),
                if (hasVideo) _ClearButton(onTap: onClear),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.secondaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.cut_rounded,
                size: 17,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '지금은 앱 안에서 영상을 보며 자르는 기능은 준비 전이에요. 12초 이내로 편집한 영상만 선택해주세요.',
                  style: AppText.body(
                    12,
                    height: 1.45,
                    color: AppColors.primary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedVideoState extends StatelessWidget {
  final String? videoName;

  const _SelectedVideoState({required this.videoName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Icon(
              Icons.movie_filter_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            videoName ?? '선택한 영상',
            style: AppText.body(
              14,
              weight: FontWeight.w900,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '업로드 후 서버에서 가볍게 압축됩니다',
            style: AppText.body(
              11,
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PickerEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 38, color: AppColors.muted),
        const SizedBox(height: 10),
        Text(
          title,
          style: AppText.body(
            14,
            weight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppText.body(11, color: AppColors.subtle),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ClearButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ClearButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 9,
      right: 9,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(7),
            child: Icon(Icons.close_rounded, size: 17, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final int? maxLength;
  final int maxLines;

  const _StyledTextField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.maxLength,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      style: AppText.body(14, weight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppText.body(13, color: AppColors.subtle),
        counterText: '',
        filled: true,
        fillColor: AppColors.surfaceLow,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 58 : 0),
          child: Icon(icon, size: 18, color: AppColors.muted),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
      ),
    );
  }
}

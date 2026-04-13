import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';

class PostComposeSheet extends ConsumerStatefulWidget {
  const PostComposeSheet({super.key});

  @override
  ConsumerState<PostComposeSheet> createState() => _PostComposeSheetState();
}

class _PostComposeSheetState extends ConsumerState<PostComposeSheet> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  Uint8List? _imageBytes;
  bool _submitting = false;

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
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() => _imageBytes = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('이미지 선택 실패: $e')));
      }
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제목을 입력해주세요')));
      return;
    }
    setState(() => _submitting = true);
    try {
      String? imageUrl;
      if (_imageBytes != null) {
        imageUrl = await FirebaseService.uploadPostImage(_imageBytes!);
      }
      await FirebaseService.createPost(
        title: title,
        content: _contentCtrl.text.trim().isEmpty ? null : _contentCtrl.text.trim(),
        imageUrl: imageUrl,
      );
      ref.invalidate(postsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('등록 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.subtle, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('새 게시물', style: AppText.headline(20))),
            TextButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('등록', style: AppText.body(15, weight: FontWeight.w700, color: AppColors.primary)),
            ),
          ]),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _submitting ? null : _pickImage,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imageBytes != null
                    ? Stack(fit: StackFit.expand, children: [
                        Image.memory(_imageBytes!, fit: BoxFit.cover),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => setState(() => _imageBytes = null),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.close_rounded, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ])
                    : Center(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_a_photo_outlined, size: 36, color: AppColors.muted),
                          const SizedBox(height: 8),
                          Text('사진 추가', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.muted)),
                          Text('탭해서 갤러리에서 선택', style: AppText.body(11, color: AppColors.subtle)),
                        ]),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleCtrl,
            maxLength: 60,
            decoration: const InputDecoration(
              hintText: '제목 (필수)',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contentCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '내용 (선택)',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
      ),
    );
  }
}

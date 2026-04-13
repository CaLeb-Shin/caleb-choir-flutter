import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/firebase_service.dart';
import '../../widgets/interactive.dart';

class SheetMusicScreen extends ConsumerWidget {
  const SheetMusicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheetMusicAsync = ref.watch(sheetMusicProvider);
    final isAdmin = ref.watch(effectiveHasManagePermissionProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('악보', style: AppText.headline(28))),
            if (isAdmin)
              IconButton(
                onPressed: () => _showAddDialog(context, ref),
                icon: const Icon(Icons.add_circle_rounded, color: AppColors.secondary),
                tooltip: '악보 추가',
              ),
          ]),
          const SizedBox(height: 4),
          Text('파트별 악보를 열람하고 연습하세요', style: AppText.body(14, color: AppColors.muted)),
          const SizedBox(height: 24),

          sheetMusicAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator())),
            error: (_, __) => const Center(child: Text('악보를 불러올 수 없습니다')),
            data: (sheets) {
              if (sheets.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  decoration: BoxDecoration(
                    color: AppColors.card, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                  ),
                  child: Column(children: [
                    Icon(Icons.music_note_rounded, size: 40, color: AppColors.subtle),
                    const SizedBox(height: 12),
                    Text('등록된 악보가 없습니다', style: AppText.body(16, weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('관리자가 업로드하면 여기에 표시됩니다', style: AppText.body(13, color: AppColors.muted)),
                  ]),
                );
              }
              return Column(
                children: sheets.map<Widget>((sheet) => Tappable(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 48, height: 60,
                        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.description_rounded, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(sheet['title'] ?? '', style: AppText.body(15, weight: FontWeight.w700)),
                        if (sheet['composer'] != null) ...[
                          const SizedBox(height: 3),
                          Text(sheet['composer'], style: AppText.body(13, color: AppColors.muted)),
                        ],
                      ])),
                      if (isAdmin)
                        IconButton(
                          onPressed: () async {
                            await FirebaseService.deleteSheetMusic(sheet['id']);
                            ref.invalidate(sheetMusicProvider);
                          },
                          icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                        )
                      else
                        const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.subtle),
                    ]),
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final composerCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('악보 추가'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: '곡 제목')),
        const SizedBox(height: 10),
        TextField(controller: composerCtrl, decoration: const InputDecoration(hintText: '작곡가 (선택)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(onPressed: () async {
          if (titleCtrl.text.trim().isNotEmpty) {
            await FirebaseService.addSheetMusic(titleCtrl.text.trim(), composer: composerCtrl.text.trim());
            ref.invalidate(sheetMusicProvider);
          }
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('추가')),
      ],
    ));
  }
}

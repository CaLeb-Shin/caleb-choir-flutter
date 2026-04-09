import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';

class SheetMusicScreen extends ConsumerWidget {
  const SheetMusicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheetMusicAsync = ref.watch(sheetMusicProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero
          Text('성가대 악보', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.secondary)),
          const SizedBox(height: 8),
          const Text('악보 도서관', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 8),
          const Text('찬양대 전체 악보를 열람하고 파트별 연습에 활용하세요.', style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 24),

          // Sheet Music List
          sheetMusicAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
            error: (_, __) => const Center(child: Text('악보를 불러올 수 없습니다')),
            data: (sheets) {
              if (sheets.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.1)),
                      child: const Icon(Icons.music_note, size: 40, color: AppColors.secondary),
                    ),
                    const SizedBox(height: 16),
                    const Text('등록된 악보가 없습니다', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    const SizedBox(height: 6),
                    const Text('관리자가 악보를 업로드하면 여기에 표시됩니다', style: TextStyle(fontSize: 14, color: AppColors.muted), textAlign: TextAlign.center),
                  ]),
                );
              }

              return Column(
                children: sheets.map<Widget>((sheet) {
                  return GestureDetector(
                    onTap: () {
                      final url = sheet['fileUrl'] as String?;
                      if (url != null) {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _PdfViewerPage(title: sheet['title'] ?? '악보', url: url),
                        ));
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface, borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 56, height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.description, color: Colors.white54, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(sheet['title'] ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          if (sheet['composer'] != null) ...[
                            const SizedBox(height: 4),
                            Text(sheet['composer'], style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                          ],
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.description, size: 14, color: AppColors.secondary),
                            const SizedBox(width: 6),
                            Text('PDF 악보 열기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                          ]),
                        ])),
                        const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
                      ]),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PdfViewerPage extends StatelessWidget {
  final String title;
  final String url;
  const _PdfViewerPage({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.picture_as_pdf, size: 64, color: AppColors.secondary),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 8),
          const Text('PDF 뷰어가 로드됩니다', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // TODO: Open PDF with flutter_pdfview or url_launcher
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('외부에서 열기'),
          ),
        ]),
      ),
    );
  }
}

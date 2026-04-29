import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../models/church.dart';
import '../../providers/app_providers.dart';
import '../../widgets/app_logo_title.dart';
import '../profile_setup/profile_setup_screen.dart';
import 'church_register_screen.dart';

/// 승인된 교회를 검색해서 선택. [requestedRole]은 'member' 또는 'part_leader'.
class ChurchSearchScreen extends ConsumerStatefulWidget {
  final String requestedRole;
  const ChurchSearchScreen({super.key, required this.requestedRole});

  @override
  ConsumerState<ChurchSearchScreen> createState() => _ChurchSearchScreenState();
}

class _ChurchSearchScreenState extends ConsumerState<ChurchSearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';
  Timer? _debouncer;

  @override
  void dispose() {
    _debouncer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debouncer?.cancel();
    _debouncer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v);
    });
  }

  void _selectChurch(Church church) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          mode: ProfileSetupMode.joinChurch,
          churchId: church.id,
          churchName: church.name,
          requestedRole: widget.requestedRole,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(churchSearchProvider(_query));
    final title = widget.requestedRole == 'part_leader'
        ? '파트장 신청 — 교회 선택'
        : '찬양대원 신청 — 교회 선택';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: AppLogoTitle(
          title: title,
          textStyle: AppText.body(15, weight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: TextField(
                controller: _ctrl,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '교회명으로 검색 (예: 갈렙)',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: result.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '검색 실패: $e',
                      style: AppText.body(13, color: AppColors.error),
                    ),
                  ),
                ),
                data: (churches) => churches.isEmpty
                    ? _EmptyState(
                        onCreate: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChurchRegisterScreen(),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: churches.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _ChurchTile(
                          church: churches[i],
                          onTap: () => _selectChurch(churches[i]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChurchTile extends StatelessWidget {
  final Church church;
  final VoidCallback onTap;
  const _ChurchTile({required this.church, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.church_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      church.name,
                      style: AppText.body(15, weight: FontWeight.w700),
                    ),
                    if (church.address != null &&
                        church.address!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        church.address!,
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: AppColors.muted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              '찾으시는 교회가 없어요',
              style: AppText.body(15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '새 교회로 직접 등록하실 수 있습니다',
              style: AppText.body(13, color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('새 교회 등록'),
            ),
          ],
        ),
      ),
    );
  }
}

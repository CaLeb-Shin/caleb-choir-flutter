import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../services/firebase_service.dart';
import '../profile_setup/profile_setup_screen.dart';

/// 새 교회 등록 폼. 이름 중복 확인 후 ProfileSetupScreen으로 이동.
class ChurchRegisterScreen extends ConsumerStatefulWidget {
  const ChurchRegisterScreen({super.key});

  @override
  ConsumerState<ChurchRegisterScreen> createState() => _ChurchRegisterScreenState();
}

class _ChurchRegisterScreenState extends ConsumerState<ChurchRegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '교회명을 입력해주세요');
      return;
    }
    setState(() { _checking = true; _error = null; });
    try {
      final taken = await FirebaseService.isChurchNameTaken(name);
      if (taken) {
        setState(() { _checking = false; _error = '이미 등록 신청된 이름입니다'; });
        return;
      }
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          mode: ProfileSetupMode.registerChurch,
          requestedRole: 'church_admin',
          churchName: name,
          pendingChurchData: {
            'name': name,
            'address': _addressCtrl.text.trim(),
            'contactPhone': _phoneCtrl.text.trim(),
            'contactEmail': _emailCtrl.text.trim(),
          },
        ),
      ));
      if (mounted) setState(() => _checking = false);
    } catch (e) {
      setState(() { _checking = false; _error = '확인 실패: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('새 교회 등록', style: AppText.body(15, weight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.secondarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.secondary),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  '플랫폼 관리자 승인 후 활성화됩니다.\n승인 시 신청자 본인이 해당 교회의 관리자가 됩니다.',
                  style: AppText.body(12, weight: FontWeight.w600, color: AppColors.secondary),
                )),
              ]),
            ),
            const SizedBox(height: 24),

            _Label(text: '교회명 *'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: '예: 갈렙 본교회'),
            ),
            const SizedBox(height: 16),

            _Label(text: '주소 (선택)'),
            const SizedBox(height: 6),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(hintText: '예: 서울시 강남구'),
            ),
            const SizedBox(height: 16),

            _Label(text: '대표 연락처 (선택)'),
            const SizedBox(height: 6),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: '010-0000-0000'),
            ),
            const SizedBox(height: 16),

            _Label(text: '대표 이메일 (선택)'),
            const SizedBox(height: 6),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'church@example.com'),
            ),
            const SizedBox(height: 24),

            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: AppText.body(13, color: AppColors.error)),
              ),

            ElevatedButton(
              onPressed: _checking ? null : _next,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _checking
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('다음: 프로필 작성'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.body(12, weight: FontWeight.w700, color: AppColors.onSurfaceVariant));
  }
}

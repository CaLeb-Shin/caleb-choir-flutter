import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/awards_provider.dart';

/// Compact pill badges shown next to a user name.
/// Active titles (current weekly/monthly Caleb, attendance champion) take
/// priority; cumulative win counts fall in after.
class UserBadges extends ConsumerWidget {
  final String? userId;
  final double height;
  final int max;

  const UserBadges({
    super.key,
    required this.userId,
    this.height = 18,
    this.max = 2,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId == null) return const SizedBox.shrink();
    final awardsAsync = ref.watch(awardsProvider);
    return awardsAsync.maybeWhen(
      data: (awards) {
        final pills = <_BadgeSpec>[];
        if (awards.isCurrentWeeklyCaleb(userId)) {
          pills.add(const _BadgeSpec('이주의 갈렙', _BadgeStyle.weeklyActive));
        }
        if (awards.isCurrentMonthlyCaleb(userId)) {
          pills.add(const _BadgeSpec('이달의 갈렙', _BadgeStyle.monthlyActive));
        }
        if (awards.isAttendanceChampion(userId)) {
          pills.add(const _BadgeSpec('출석챔피언', _BadgeStyle.champion));
        }
        final c = awards.countsFor(userId);
        if (c.weeklyCalebWins > 0) {
          pills.add(_BadgeSpec('주간갈렙 ${c.weeklyCalebWins}회', _BadgeStyle.weeklyCount));
        }
        if (c.monthlyCalebWins > 0) {
          pills.add(_BadgeSpec('월간갈렙 ${c.monthlyCalebWins}회', _BadgeStyle.monthlyCount));
        }
        if (pills.isEmpty) return const SizedBox.shrink();
        final shown = pills.take(max).toList();
        return Wrap(spacing: 4, runSpacing: 3, children: [
          for (final p in shown) _Pill(spec: p, height: height),
        ]);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

enum _BadgeStyle { weeklyActive, monthlyActive, champion, weeklyCount, monthlyCount }

class _BadgeSpec {
  final String label;
  final _BadgeStyle style;
  const _BadgeSpec(this.label, this.style);
}

class _Pill extends StatelessWidget {
  final _BadgeSpec spec;
  final double height;
  const _Pill({required this.spec, required this.height});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(spec.style);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      child: Text(
        spec.label,
        style: AppText.body(10, weight: FontWeight.w700, color: fg),
      ),
    );
  }

  (Color, Color) _colors(_BadgeStyle s) {
    switch (s) {
      case _BadgeStyle.weeklyActive:
        return (const Color(0xFFFEF3C7), const Color(0xFFB45309)); // amber
      case _BadgeStyle.monthlyActive:
        return (const Color(0xFFFCE7F3), const Color(0xFFBE185D)); // pink
      case _BadgeStyle.champion:
        return (const Color(0xFFDCFCE7), const Color(0xFF15803D)); // green
      case _BadgeStyle.weeklyCount:
        return (const Color(0xFFFEF9C3), const Color(0xFF854D0E)); // soft yellow
      case _BadgeStyle.monthlyCount:
        return (const Color(0xFFFAE8FF), const Color(0xFF86198F)); // soft purple
    }
  }
}

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../theme/app_theme.dart';

/// In-app viewer that shows a part's sheet (PDF or image) while a translucent
/// audio player floats over it — so a member can read the score and listen to
/// the guide / MR at the same time without leaving the app.
class SheetViewerScreen extends StatelessWidget {
  final String title;
  final String partLabel;
  final String? sheetUrl;
  final String? guideAudioUrl;
  final String? mrAudioUrl;

  const SheetViewerScreen({
    super.key,
    required this.title,
    required this.partLabel,
    this.sheetUrl,
    this.guideAudioUrl,
    this.mrAudioUrl,
  });

  bool get _hasSheet => sheetUrl != null && sheetUrl!.isNotEmpty;
  bool get _hasAudio =>
      (guideAudioUrl?.isNotEmpty ?? false) || (mrAudioUrl?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$title · $partLabel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.headline(18),
        ),
      ),
      // Sheet fills the body; the player floats on top (translucent) so the
      // score stays visible behind it.
      body: Stack(
        children: [
          Positioned.fill(
            child: _hasSheet
                ? _SheetView(url: sheetUrl!)
                : Center(
                    child: Text(
                      '악보가 없습니다',
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                  ),
          ),
          if (_hasAudio)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SheetAudioBar(guideUrl: guideAudioUrl, mrUrl: mrAudioUrl),
            ),
        ],
      ),
    );
  }
}

bool _isPdfUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  return path.endsWith('.pdf');
}

class _SheetView extends StatelessWidget {
  final String url;
  const _SheetView({required this.url});

  @override
  Widget build(BuildContext context) {
    if (_isPdfUrl(url)) {
      return PdfViewer.uri(
        Uri.parse(url),
        params: const PdfViewerParams(margin: 8),
      );
    }
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stack) => Center(
            child: Text(
              '악보를 불러올 수 없습니다',
              style: AppText.body(14, color: AppColors.muted),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetAudioBar extends StatefulWidget {
  final String? guideUrl;
  final String? mrUrl;

  const _SheetAudioBar({this.guideUrl, this.mrUrl});

  @override
  State<_SheetAudioBar> createState() => _SheetAudioBarState();
}

class _SheetAudioBarState extends State<_SheetAudioBar> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  bool _isMr = false;
  bool _playing = false;
  bool _loading = false;
  String? _loadedUrl;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  String? get _guide =>
      (widget.guideUrl?.isNotEmpty ?? false) ? widget.guideUrl : null;
  String? get _mr => (widget.mrUrl?.isNotEmpty ?? false) ? widget.mrUrl : null;
  String? get _currentUrl => _isMr ? _mr : _guide;

  @override
  void initState() {
    super.initState();
    _isMr = _guide == null && _mr != null;
    _subs.add(
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _pos = p);
      }),
    );
    _subs.add(
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _dur = d);
      }),
    );
    _subs.add(
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }),
    );
    _subs.add(
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playing = false;
            _pos = Duration.zero;
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final url = _currentUrl;
    if (url == null) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() => _loading = true);
    try {
      if (_loadedUrl != url) {
        await _player.play(UrlSource(url));
        _loadedUrl = url;
      } else {
        await _player.resume();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Switch guide <-> MR while keeping the same playback position (and play
  /// state), so you can A/B the two tracks at the same spot.
  Future<void> _switchTo(bool toMr) async {
    if (toMr == _isMr) return;
    final url = toMr ? _mr : _guide;
    if (url == null) return;
    final resumePos = _pos;
    final wasPlaying = _playing;
    setState(() {
      _isMr = toMr;
      _loading = true;
    });
    try {
      await _player.play(UrlSource(url));
      _loadedUrl = url;
      if (resumePos > Duration.zero) {
        await _player.seek(resumePos);
        if (mounted) setState(() => _pos = resumePos);
      }
      if (!wasPlaying) {
        await _player.pause();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seekBy(int seconds) async {
    if (_dur <= Duration.zero) return;
    var target = _pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > _dur) target = _dur;
    await _player.seek(target);
    if (mounted) setState(() => _pos = target);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _dur.inMilliseconds <= 0
        ? 1.0
        : _dur.inMilliseconds.toDouble();
    final value = _pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final showToggle = _guide != null && _mr != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            // Light blur + low tint: the score behind stays readable through it.
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.45),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _scrubber(value, maxMs),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Left slot holds the toggle; an equal-width empty slot
                        // on the right keeps the transport centered.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: showToggle
                                ? _toggle()
                                : const SizedBox.shrink(),
                          ),
                        ),
                        _skipButton(forward: false, onTap: () => _seekBy(-3)),
                        const SizedBox(width: 22),
                        _playButton(),
                        const SizedBox(width: 22),
                        _skipButton(forward: true, onTap: () => _seekBy(3)),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('가이드', !_isMr, () => _switchTo(false)),
          _segment('MR', _isMr, () => _switchTo(true)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppText.body(
            11.5,
            weight: FontWeight.w800,
            color: active ? Colors.white : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _skipButton({required bool forward, required VoidCallback onTap}) {
    return IconButton(
      onPressed: onTap,
      tooltip: forward ? '3초 앞으로' : '3초 뒤로',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 50, minHeight: 50),
      icon: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Material has no replay_3 / forward_3, so draw a circular arrow
            // (mirrored for forward) and overlay the "3".
            Transform(
              alignment: Alignment.center,
              transform: forward
                  ? Matrix4.diagonal3Values(-1, 1, 1)
                  : Matrix4.identity(),
              child: Icon(
                Icons.replay_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                '3',
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playButton() {
    return GestureDetector(
      onTap: _loading ? null : _togglePlay,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.32),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(17),
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 34,
                color: Colors.white,
              ),
      ),
    );
  }

  Widget _scrubber(double value, double maxMs) {
    return Row(
      children: [
        Text(_fmt(_pos), style: AppText.body(10.5, color: AppColors.muted)),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withValues(alpha: 0.18),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
            ),
            child: Slider(
              value: value,
              max: maxMs,
              onChanged: (v) =>
                  setState(() => _pos = Duration(milliseconds: v.round())),
              onChangeEnd: (v) =>
                  _player.seek(Duration(milliseconds: v.round())),
            ),
          ),
        ),
        Text(_fmt(_dur), style: AppText.body(10.5, color: AppColors.muted)),
      ],
    );
  }
}

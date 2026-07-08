import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// Shows the short step-by-step tutorial on first launch.
Future<void> showTutorial(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _TutorialDialog(),
  );
}

class _TutStep {
  const _TutStep(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

List<_TutStep> _stepsFor(AppLocalizations t) => [
      _TutStep(Icons.lightbulb_outline_rounded, t.tutWelcomeTitle,
          t.tutWelcomeBody),
      _TutStep(Icons.style_rounded, t.tutCardsTitle, t.tutCardsBody),
      _TutStep(Icons.grid_view_rounded, t.tutCortexTitle, t.tutCortexBody),
      _TutStep(Icons.lock_rounded, t.tutCryptTitle, t.tutCryptBody),
      _TutStep(Icons.tips_and_updates_outlined, t.tutTipsTitle, t.tutTipsBody),
    ];


class _TutorialDialog extends StatefulWidget {
  const _TutorialDialog();

  @override
  State<_TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<_TutorialDialog> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _stepsFor(context.t).length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = _stepsFor(context.t);
    final last = _page == steps.length - 1;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassEdge(
        borderRadius: 28,
        blur: 0,
        fill: AppPalette.cardFill,
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 250,
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final s in steps)
                    Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppPalette.chipFill,
                          ),
                          child: Icon(s.icon,
                              size: 28, color: AppPalette.inkPrimary),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.inkPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              s.body,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.45,
                                color: AppPalette.inkSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < steps.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppPalette.inkPrimary
                          : AppPalette.selFill,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.t.skip,
                      style: TextStyle(color: AppPalette.inkSecondary)),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _next,
                  child: Text(last ? context.t.getStarted : context.t.next),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One figure and its caption inside a [StatCard].
class Stat {
  const Stat(this.value, this.label);
  final String value;
  final String label;
}

/// A rounded panel of three or four figures, evenly divided — the little
/// "at a glance" summary that sits above a feed.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.stats});

  final List<Stat> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: AppPalette.bubbleGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final stat in stats)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stat.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stat.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: AppPalette.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

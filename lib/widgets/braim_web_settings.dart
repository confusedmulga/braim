import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../web/web_controller.dart';
import 'glass.dart';

/// The Braim Web panel in Settings: the switch, and while it's on, the
/// address to open, the pairing code, the linked browsers and the trust note.
/// The code is shown here only, never in the notification.
class BraimWebSettings extends StatefulWidget {
  const BraimWebSettings({super.key});

  @override
  State<BraimWebSettings> createState() => _BraimWebSettingsState();
}

class _BraimWebSettingsState extends State<BraimWebSettings> {
  /// Redraws once a second while on, for the code's countdown (the code
  /// itself renews when read) and the browsers' last-used times.
  Timer? _ticker;

  void _syncTicker(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static const _subtitle = TextStyle(color: Color(0xFF5E5F69));

  String _offLine(BuildContext context, BraimWebController web) {
    switch (web.startError) {
      case WebStartError.noNetwork:
        return context.t.webNoNetwork;
      case WebStartError.failed:
        return context.t.webStartFailed;
      case null:
        break;
    }
    if (web.stopReason == WebStopReason.autoOff) return context.t.webAutoOff;
    return context.t.webHint;
  }

  @override
  Widget build(BuildContext context) {
    final web = context.watch<BraimWebController>();
    _syncTicker(web.running);
    final t = context.t;
    final problem =
        !web.running &&
        (web.startError != null || web.stopReason == WebStopReason.autoOff);

    return GlassPanel(
      borderRadius: 20,
      blur: 0,
      color: AppPalette.surfaceGlass,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: Icon(Icons.laptop_rounded, color: AppPalette.inkPrimary),
            title: Text(
              t.webToggle,
              style: TextStyle(color: AppPalette.inkPrimary),
            ),
            subtitle: Text(
              web.running ? t.webKeepOpen : _offLine(context, web),
              style: problem
                  ? TextStyle(color: AppPalette.scheme.error)
                  : _subtitle,
            ),
            value: web.running,
            onChanged: web.busy ? null : (on) => on ? web.start() : web.stop(),
          ),
          if (web.running) _OnDetails(web: web),
        ],
      ),
    );
  }
}

class _OnDetails extends StatelessWidget {
  const _OnDetails({required this.web});

  final BraimWebController web;

  static String _lastSeen(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat('h:mm a').format(t);
    }
    return DateFormat('MMM d').format(t);
  }

  /// "482913" as "482 913", easier to read and type.
  static String _grouped(String code) =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final label = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: AppPalette.inkSecondary,
    );
    final code = web.pairingCode ?? '';
    final secondsLeft = (web.codeTimeLeft.inMilliseconds / 1000).ceil();
    final sessions = web.sessions;
    final addresses = web.addresses;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.webAddressLabel, style: label),
          const SizedBox(height: 4),
          if (addresses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                t.webNoNetwork,
                style: TextStyle(color: AppPalette.scheme.error),
              ),
            ),
          for (final url in addresses)
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    url,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.inkPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t.copy,
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 20,
                    color: AppPalette.inkSecondary,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(t.copied)));
                  },
                ),
              ],
            ),
          const SizedBox(height: 14),
          Text(t.webCodeLabel, style: label),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _grouped(code),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppPalette.inkPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  t.webCodeExpires(secondsLeft),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppPalette.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(t.webLinkedBrowsers, style: label),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t.webNoBrowsers, style: _subtitleStyle),
            ),
          for (final s in sessions)
            Row(
              children: [
                Icon(
                  Icons.public_rounded,
                  size: 20,
                  color: AppPalette.inkSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppPalette.inkPrimary,
                          ),
                        ),
                        Text(
                          t.webLastSeen(_lastSeen(s.lastSeen)),
                          style: _subtitleStyle,
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => web.logOut(s.id),
                  child: Text(t.webLogOut),
                ),
              ],
            ),
          if (sessions.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: web.logOutAll,
                child: Text(t.webLogOutAll),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppPalette.inkSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.webTrustNote,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppPalette.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _subtitleStyle = TextStyle(color: Color(0xFF5E5F69));
}

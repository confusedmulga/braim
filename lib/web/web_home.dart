import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../platform/web_bridge.dart';
import '../screens/root_shell.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import 'web_library_actions.dart';

/// What a browser-only library opens to: the usual shell, or — while the
/// library is empty and the user hasn't chosen to start fresh — a welcome that
/// brings a phone backup in.
class WebLocalHome extends StatefulWidget {
  const WebLocalHome({super.key});

  static const _startedFreshKey = 'braim.startedFresh';

  @override
  State<WebLocalHome> createState() => _WebLocalHomeState();
}

class _WebLocalHomeState extends State<WebLocalHome> {
  bool _startedFresh = webStorageGet(WebLocalHome._startedFreshKey) == '1';

  void _startFresh() {
    webStorageSet(WebLocalHome._startedFreshKey, '1');
    setState(() => _startedFresh = true);
  }

  @override
  Widget build(BuildContext context) {
    final empty = context.select<AppState, bool>((s) => s.isLibraryEmpty);
    if (!empty || _startedFresh) return const RootShell();
    return _WelcomeScreen(onStartFresh: _startFresh);
  }
}

class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen({required this.onStartFresh});

  final VoidCallback onStartFresh;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      body: AppBackground(
        wallpaper: true,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: GlassPanel(
                borderRadius: 28,
                strong: true,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset('assets/logo_icon.png',
                          width: 52, height: 52, cacheWidth: 156),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      t.webWelcomeTitle,
                      style: TextStyle(
                        fontFamily: kNoteHeadingFont,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t.webWelcomeBody,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () =>
                            WebLibraryActions.pickAndImport(context),
                        icon: const Icon(Icons.upload_file_rounded),
                        label: Text(t.webImportBackup),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t.webImportHint,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onStartFresh,
                        child: Text(t.webStartEmpty),
                      ),
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
}

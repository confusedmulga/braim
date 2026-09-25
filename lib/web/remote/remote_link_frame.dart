import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/store/remote_library_store.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Wraps the app in remote mode: shows the link to the phone (a small pill
/// while reconnecting; after a minute out of reach the page stops taking
/// edits, since the browser holds no durable copy), wires the Crypt re-lock,
/// and reports activity so an unlocked Crypt doesn't time out mid-use.
class RemoteLinkFrame extends StatefulWidget {
  const RemoteLinkFrame({super.key, required this.store, required this.child});

  final RemoteLibraryStore store;
  final Widget child;

  @override
  State<RemoteLinkFrame> createState() => _RemoteLinkFrameState();
}

class _RemoteLinkFrameState extends State<RemoteLinkFrame> {
  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    widget.store.onCryptLocked = state.forgetLocally;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.store.markActive(),
      child: ValueListenableBuilder<PhoneLinkState>(
        valueListenable: widget.store.status,
        builder: (context, link, _) {
          final blocked = link == PhoneLinkState.offline ||
              link == PhoneLinkState.revoked;
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (blocked)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: _Banner(
                        text: t.webOfflineReadOnly,
                        spinner: link == PhoneLinkState.offline,
                      ),
                    ),
                  ),
                )
              else if (link == PhoneLinkState.reconnecting)
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                        child: _Banner(text: t.webReconnecting, spinner: true)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.spinner});

  final String text;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.scheme.inverseSurface,
      borderRadius: BorderRadius.circular(22),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppPalette.scheme.onInverseSurface,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: AppPalette.scheme.onInverseSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

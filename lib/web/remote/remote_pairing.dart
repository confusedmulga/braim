import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../l10n/l10n.dart';
import '../../platform/web_bridge.dart';
import '../../services/store/remote_protocol.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import 'remote_boot.dart';

/// Pairing with the phone that served this page: the code from the QR/URL is
/// sent once; the phone's owner allows this computer on the phone; the phone
/// hands back a session token.
class RemotePairingApp extends StatelessWidget {
  const RemotePairingApp({
    super.key,
    required this.origin,
    required this.code,
    required this.onPaired,
  });

  final String origin;
  final String? code;
  final void Function(String token, bool remember) onPaired;

  @override
  Widget build(BuildContext context) => RemoteShellApp(
        builder: (_) =>
            _PairingFlow(origin: origin, code: code, onPaired: onPaired),
      );
}

enum _Step { enterCode, confirm, waiting, denied, expired, failed }

class _PairingFlow extends StatefulWidget {
  const _PairingFlow(
      {required this.origin, required this.code, required this.onPaired});

  final String origin;
  final String? code;
  final void Function(String token, bool remember) onPaired;

  @override
  State<_PairingFlow> createState() => _PairingFlowState();
}

class _PairingFlowState extends State<_PairingFlow> {
  late _Step _step = widget.code == null ? _Step.enterCode : _Step.confirm;
  late final _codeCtrl = TextEditingController(text: widget.code ?? '');
  bool _remember = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _step = _Step.waiting);
    try {
      final res = await http
          .post(Uri.parse('${widget.origin}${RemoteApi.pair}'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'code': code,
                'name': webDeviceLabel(),
                'remember': _remember,
              }))
          .timeout(const Duration(minutes: 3));
      if (res.statusCode == 200) {
        final token = '${(jsonDecode(res.body) as Map)['token']}';
        widget.onPaired(token, _remember);
        return;
      }
      final err = errorOf(res);
      setState(() => _step = switch (err) {
            'denied' => _Step.denied,
            'expired' || 'bad-code' => _Step.expired,
            _ => _Step.failed,
          });
    } catch (_) {
      if (mounted) setState(() => _step = _Step.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return switch (_step) {
      _Step.enterCode => RemoteMessageCard(
          icon: Icons.qr_code_2_rounded,
          title: t.webPairTitle,
          body: t.webPairBody,
          extra: TextField(
            controller: _codeCtrl,
            decoration: const InputDecoration(
              labelText: 'Code',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => setState(() => _step = _Step.confirm),
          ),
          action: FilledButton(
            onPressed: () => setState(() => _step = _Step.confirm),
            child: Text(t.save),
          ),
        ),
      _Step.confirm => RemoteMessageCard(
          icon: Icons.phonelink_rounded,
          title: t.webPairTitle,
          body: t.openOnComputerTrusted,
          extra: CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text(t.webPairRemember),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          action: FilledButton(onPressed: _pair, child: Text(t.pairAllow)),
        ),
      _Step.waiting => RemoteMessageCard(
          icon: Icons.phone_android_rounded,
          title: t.webPairTitle,
          body: t.webPairWaiting,
          extra: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        ),
      _Step.denied => RemoteMessageCard(
          icon: Icons.block_rounded,
          title: t.webPairTitle,
          body: t.webPairDenied,
        ),
      _Step.expired => RemoteMessageCard(
          icon: Icons.timer_off_rounded,
          title: t.webPairTitle,
          body: t.webPairExpired,
          action: TextButton(
            onPressed: () => setState(() {
              _codeCtrl.clear();
              _step = _Step.enterCode;
            }),
            child: Text(t.retry),
          ),
        ),
      _Step.failed => RemoteMessageCard(
          icon: Icons.wifi_off_rounded,
          title: t.webPairTitle,
          body: t.webOfflineReadOnly,
          action: TextButton(onPressed: _pair, child: Text(t.retry)),
        ),
    };
  }
}

/// The card the pre-app screens (pairing, can't reach the phone) are built from.
class RemoteMessageCard extends StatelessWidget {
  const RemoteMessageCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 28,
      strong: true,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: AppPalette.scheme.primary),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                fontFamily: kNoteHeadingFont,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppPalette.inkPrimary,
              )),
          const SizedBox(height: 10),
          Text(body,
              style: TextStyle(
                  fontSize: 15, height: 1.45, color: AppPalette.inkSecondary)),
          if (extra != null) ...[const SizedBox(height: 16), extra!],
          if (action != null) ...[
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
  }
}

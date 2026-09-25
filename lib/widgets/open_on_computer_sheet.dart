import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';

import '../l10n/l10n.dart';
import '../services/phone_server/phone_server.dart';
import '../services/phone_server/phone_server_controller.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Settings → "Open on computer": starts the phone server and shows the
/// address (and a QR code) a browser on the same Wi-Fi or hotspot opens.
Future<void> showOpenOnComputerSheet(BuildContext context) async {
  final state = context.read<AppState>();
  final PhoneServer server;
  try {
    server = await PhoneServerController.instance.start(state);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.somethingWrong)));
    return;
  }
  if (server.pairingCode == null) server.newPairingCode();
  final addresses = await PhoneServer.lanAddresses();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.sheet,
    showDragHandle: true,
    builder: (_) => _Sheet(server: server, addresses: addresses),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.server, required this.addresses});

  final PhoneServer server;
  final List<String> addresses;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        // A used or expired code is replaced, so the next computer can pair.
        if (server.running && server.pairingCode == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => server.newPairingCode());
        }
        final code = server.pairingCode ?? '';
        final port = server.boundPort ?? 0;
        final urls = [
          for (final a in addresses)
            port == 80 ? 'http://$a/#p=$code' : 'http://$a:$port/#p=$code',
        ];
        final connected = server.connectedDevices;
        final paired = server.devices.all;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.openOnComputerSheetTitle,
                    style: TextStyle(
                        fontFamily: kNoteHeadingFont,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary)),
                const SizedBox(height: 8),
                Text(
                  urls.isEmpty
                      ? t.openOnComputerNoNetwork
                      : t.openOnComputerSheetBody,
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: AppPalette.inkSecondary),
                ),
                if (urls.isNotEmpty && server.running) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SizedBox.square(
                        dimension: 208,
                        child: CustomPaint(painter: _QrPainter(urls.first)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final u in urls)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(Icons.link_rounded,
                          color: AppPalette.inkPrimary),
                      title: SelectableText(u,
                          style: TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 12.5,
                              color: AppPalette.inkPrimary)),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: u)),
                      ),
                    ),
                ],
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: AppPalette.inkSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(t.openOnComputerTrusted,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AppPalette.inkSecondary)),
                    ),
                  ],
                ),
                if (connected.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(t.openOnComputerRunning,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary)),
                  for (final name in connected)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(Icons.computer_rounded,
                          color: AppPalette.scheme.primary),
                      title: Text(name,
                          style: TextStyle(color: AppPalette.inkPrimary)),
                    ),
                ],
                const SizedBox(height: 16),
                Text(t.pairedDevices,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary)),
                if (paired.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(t.pairedDevicesNone,
                        style: TextStyle(color: AppPalette.inkSecondary)),
                  ),
                for (final d in paired)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.devices_rounded,
                        color: AppPalette.inkPrimary),
                    title: Text(d.name,
                        style: TextStyle(color: AppPalette.inkPrimary)),
                    trailing: TextButton(
                      onPressed: () => server.revoke(d.tokenHash),
                      child: Text(t.pairRevoke),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(t.openOnComputerStop),
                    onPressed: () async {
                      await PhoneServerController.instance.stop();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data)
      : _image = QrImage(QrCode.fromData(
            data: data, errorCorrectLevel: QrErrorCorrectLevel.M));

  final String data;
  final QrImage _image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _image.moduleCount;
    final cell = size.width / n;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (_image.isDark(y, x)) {
          canvas.drawRect(
              Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}

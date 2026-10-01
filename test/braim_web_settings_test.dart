import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shelf/shelf.dart' show Request;

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/services/braim_web_service.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/theme/app_theme.dart';
import 'package:braim/web/web_assets.dart';
import 'package:braim/web/web_auth.dart';
import 'package:braim/web/web_controller.dart';
import 'package:braim/web/web_security.dart';
import 'package:braim/widgets/braim_web_settings.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

class _QuietService implements BraimWebService {
  @override
  set onStopRequested(void Function()? callback) {}

  @override
  Future<void> start({
    required String url,
    required String title,
    required String turnOff,
    required String channelName,
  }) async {}

  @override
  Future<void> update({
    required String url,
    required String title,
    required String turnOff,
  }) async {}

  @override
  Future<void> stop() async {}
}

Future<ByteData> _loadFromDisk(String key) async =>
    ByteData.sublistView(await File(key).readAsBytes());

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_web_settings_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<(AppState, BraimWebController)> pumpPanel(
    WidgetTester tester, {
    List<String> ips = const ['192.168.1.23'],
  }) async {
    final state = AppState();
    final web = BraimWebController(
      state,
      openSessions: () async =>
          WebSessionStore(File('${root.path}/${WebSessionStore.fileName}')),
      assets: WebAssets(load: _loadFromDisk),
      service: _QuietService(),
      listAddresses: () async => ips,
      bindAddress: InternetAddress.loopbackIPv4,
      ports: const [0],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: web),
        ],
        child: MaterialApp(
          theme: buildTheme(false),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BraimWebSettings()),
          ),
        ),
      ),
    );
    return (state, web);
  }

  Future<void> close(
    WidgetTester tester,
    AppState state,
    BraimWebController web,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await web.debugServer?.stop();
    });
    web.dispose();
    state.dispose();
  }

  /// Runs [press] outside the test's fake clock and lets its work finish.
  Future<void> realPress(WidgetTester tester, void Function() press) =>
      tester.runAsync(() async {
        press();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

  testWidgets('off: the switch and the same-Wi-Fi hint', (tester) async {
    final (state, web) = await pumpPanel(tester);
    expect(find.text('Open Braim on your computer'), findsOneWidget);
    expect(
      find.text(
        "Works on the same Wi-Fi, or when your computer joins this "
        "phone's hotspot.",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('http://'), findsNothing);
    expect(find.text('Pairing code'), findsNothing);
    await close(tester, state, web);
  });

  testWidgets('with no Wi-Fi or hotspot, it says so and stays off', (
    tester,
  ) async {
    final (state, web) = await pumpPanel(tester, ips: const []);
    await tester.runAsync(web.start);
    await tester.pump();
    expect(web.running, isFalse);
    expect(
      find.text('Connect to Wi-Fi or turn on your hotspot first'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await close(tester, state, web);
  });

  testWidgets(
    'on: address, grouped code with countdown, browsers, trust note',
    (tester) async {
      final (state, web) = await pumpPanel(tester);
      await tester.runAsync(web.start);
      await tester.pump();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('Open this address on your computer'), findsOneWidget);
      expect(find.text('http://192.168.1.23:${web.port}'), findsOneWidget);
      final code = web.pairingCode!;
      expect(
        find.text('${code.substring(0, 3)} ${code.substring(3)}'),
        findsOneWidget,
      );
      expect(find.text('New code in 120s'), findsOneWidget);
      expect(find.text('No browser is linked yet.'), findsOneWidget);
      expect(
        find.textContaining('Anyone on this Wi-Fi could read the traffic'),
        findsOneWidget,
      );
      // The code never leaves Settings for the notification: the panel is the
      // only place it is drawn.
      expect(find.textContaining(code.substring(0, 3)), findsOneWidget);

      // A browser pairs; the panel lists it within a second.
      await tester.runAsync(() async {
        final host = '127.0.0.1:${web.port}';
        final r = await web.debugServer!.handler(
          Request(
            'POST',
            Uri.parse('http://$host/api/pair'),
            headers: {
              'host': host,
              'content-type': 'application/json',
              'user-agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/140.0',
            },
            body: '{"code":"$code"}',
            context: {kConnectionInfoKey: _Loopback()},
          ),
        );
        expect(r.statusCode, 200);
      });
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Chrome on Windows'), findsOneWidget);
      expect(find.textContaining('Last used'), findsOneWidget);

      // The panel's buttons start file and socket work, so they're pressed in
      // the real zone, where that work can finish.
      await realPress(
        tester,
        () => tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Log out'))
            .onPressed!(),
      );
      await tester.pump();
      expect(find.text('Chrome on Windows'), findsNothing);
      expect(web.sessions, isEmpty);

      // The switch turns it off.
      await realPress(
        tester,
        () => tester.widget<Switch>(find.byType(Switch)).onChanged!(false),
      );
      await tester.pump();
      expect(web.running, isFalse);
      expect(find.text('Pairing code'), findsNothing);
      await close(tester, state, web);
    },
  );
}

class _Loopback implements HttpConnectionInfo {
  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;

  @override
  int get remotePort => 50000;

  @override
  int get localPort => 8420;
}

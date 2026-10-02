import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/services/notification_service.dart';
import 'package:braim/widgets/reminder_hint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The Android side of the notifications plugin, faked at its method channel:
  // whether exact alarms are allowed, and what the user picks on the
  // "Alarms & reminders" screen.
  var exact = false;
  var allowOnScreen = false;
  final calls = <String>[];
  var rearmed = 0;

  setUpAll(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'initialize':
            return true;
          case 'canScheduleExactNotifications':
            return exact;
          case 'requestExactAlarmsPermission':
            exact = allowOnScreen;
            return allowOnScreen;
        }
        return null;
      },
    );
    NotificationService.onExactAlarmsGranted = () => rearmed++;
    // Set up once here, on the real clock: its time-zone lookup goes to a
    // channel nothing answers, and inside a widget test's fake clock that
    // reply would never arrive.
    await NotificationService.instance.init();
  });

  setUp(() {
    exact = false;
    allowOnScreen = false;
    calls.clear();
    rearmed = 0;
  });

  /// A blank screen with the app's strings; returns a context inside it.
  Future<BuildContext> pumpScreen(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));
    return ctx;
  }

  const lateText =
      'Reminders may arrive a few minutes late while exact alarms are off.';

  testWidgets('says nothing when reminders will fire on time', (tester) async {
    exact = true;
    final ctx = await pumpScreen(tester);
    await showReminderHint(ctx, notificationsAllowed: true);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('notifications off comes first: they would never show',
      (tester) async {
    final ctx = await pumpScreen(tester);
    await showReminderHint(ctx, notificationsAllowed: false);
    await tester.pump();
    expect(find.text('Turn on notifications to get reminders.'),
        findsOneWidget);
    expect(find.text(lateText), findsNothing);
  });

  testWidgets('exact alarms off: Turn on opens the screen, then re-arms',
      (tester) async {
    allowOnScreen = true;
    final ctx = await pumpScreen(tester);
    await showReminderHint(ctx, notificationsAllowed: true);
    await tester.pump();
    expect(find.text(lateText), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500)); // slide-in done
    await tester.tap(find.text('Turn on'));
    await tester.pump();
    expect(calls, contains('requestExactAlarmsPermission'));
    expect(rearmed, 1);
  });

  testWidgets('declined on the screen: nothing is re-armed', (tester) async {
    final ctx = await pumpScreen(tester);
    await showReminderHint(ctx, notificationsAllowed: true);
    await tester.pump(); // starts the slide-in
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Turn on'));
    await tester.pump();
    expect(calls, contains('requestExactAlarmsPermission'));
    expect(rearmed, 0);
  });

  testWidgets('the hint goes away on its own', (tester) async {
    final ctx = await pumpScreen(tester);
    await showReminderHint(ctx, notificationsAllowed: true);
    await tester.pump();
    expect(find.text(lateText), findsOneWidget);
    // Its 6 s countdown starts once it has finished sliding in.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}

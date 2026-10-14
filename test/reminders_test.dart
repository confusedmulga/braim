import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:braim/models/impulse.dart';
import 'package:braim/models/note.dart';
import 'package:braim/services/notification_service.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// Reminders live only as long as the note or task they belong to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  // The Android side of the notifications plugin, faked at its channel.
  final scheduled = <Map<dynamic, dynamic>>[];
  final cancelled = <int>[];
  var pending = <Map<String, Object?>>[];

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('braim_reminders_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        switch (call.method) {
          case 'initialize':
          case 'canScheduleExactNotifications':
            return true;
          case 'zonedSchedule':
            scheduled.add(call.arguments as Map);
            return null;
          case 'cancel':
            cancelled.add((call.arguments as Map)['id'] as int);
            return null;
          case 'pendingNotificationRequests':
            return pending;
        }
        return null;
      },
    );
    await NotificationService.instance.init();
    // The time-zone lookup has no platform here: run on UTC.
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  final states = <AppState>[];
  Future<AppState> boot(AppData data) async {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await StorageService.instance.save(data);
    final state = AppState();
    states.add(state);
    await state.init();
    return state;
  }

  setUp(() {
    scheduled.clear();
    cancelled.clear();
    pending = [];
  });

  tearDown(() async {
    for (final s in states) {
      await s.flushNow();
      s.dispose();
    }
    states.clear();
  });

  /// Lets the unawaited platform calls land.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  Thread remindedThread({bool once = false}) => Thread(
        title: 'Stretch',
        once: once,
      )
        ..notify = true
        ..reminderMinutes = 9 * 60;

  int threadId(Thread t) => NotificationService.idFor(t.id);

  test('deleting a reflex cancels its task reminders', () async {
    final thread = remindedThread();
    final state = await boot(AppData(
      notes: [],
      spaces: [],
      cards: [],
      impulses: [Impulse(title: 'Morning', threads: [thread])],
    ));
    await settle();
    cancelled.clear();

    await state.deleteImpulse(state.impulses.single.id);
    await settle();
    expect(cancelled, contains(threadId(thread)));
  });

  test('archiving a reflex cancels its reminders; unarchiving brings them back',
      () async {
    final thread = remindedThread();
    final state = await boot(AppData(
      notes: [],
      spaces: [],
      cards: [],
      impulses: [Impulse(title: 'Morning', threads: [thread])],
    ));
    final id = state.impulses.single.id;
    await settle();
    cancelled.clear();
    scheduled.clear();

    await state.setImpulseArchived(id, true);
    await settle();
    expect(cancelled, contains(threadId(thread)));

    await state.setImpulseArchived(id, false);
    await settle();
    expect(scheduled.map((s) => s['id']), contains(threadId(thread)));
  });

  test('a one-time task stops reminding once it is done', () async {
    final thread = remindedThread(once: true);
    final state = await boot(AppData(
      notes: [],
      spaces: [],
      cards: [],
      impulses: [Impulse(title: 'Errands', threads: [thread])],
    ));
    final id = state.impulses.single.id;
    await settle();
    cancelled.clear();

    await state.toggleThread(id, thread.id);
    await settle();
    expect(cancelled, contains(threadId(thread)));

    // Re-armed at the next launch? Not while it stays done.
    scheduled.clear();
    state.rescheduleReminders();
    await settle();
    expect(scheduled.map((s) => s['id']), isNot(contains(threadId(thread))));
  });

  test('reminders of notes and tasks no longer in the library are cancelled',
      () async {
    final kept = Note(
      id: 'kept',
      title: 'Call back',
      reminderAt: DateTime.now().add(const Duration(days: 1)),
    );
    final state = await boot(AppData(notes: [kept], spaces: [], cards: []));
    await settle();
    // What the OS still holds: one for a note a restore dropped, and one for
    // the note still here.
    pending = [
      {'id': NotificationService.idFor('gone'), 'title': 'Old', 'body': ''},
      {'id': NotificationService.idFor('kept'), 'title': 'Call back', 'body': ''},
    ];
    cancelled.clear();

    state.rescheduleReminders();
    await settle();
    expect(cancelled, contains(NotificationService.idFor('gone')));
    expect(cancelled, isNot(contains(NotificationService.idFor('kept'))));
  });

  test('clearing all data cancels note reminders', () async {
    final note = Note(
      id: 'n',
      title: 'Dentist',
      reminderAt: DateTime.now().add(const Duration(days: 1)),
    );
    final state = await boot(AppData(notes: [note], spaces: [], cards: []));
    await settle();
    pending = [
      {'id': NotificationService.idFor('n'), 'title': 'Dentist', 'body': ''},
    ];
    cancelled.clear();

    await state.clearAll();
    await settle();
    expect(cancelled, contains(NotificationService.idFor('n')));
  });

  test('restoring a deleted note brings its reminder back', () async {
    final note = Note(
      id: 'n',
      title: 'Dentist',
      reminderAt: DateTime.now().add(const Duration(days: 1)),
    );
    final state = await boot(AppData(notes: [note], spaces: [], cards: []));
    await state.deleteNote('n');
    await settle();
    scheduled.clear();

    await state.restoreNote('n');
    await settle();
    expect(scheduled.map((s) => s['id']), contains(NotificationService.idFor('n')));
  });

  test('a reminder for a Crypt note shows nothing of the note', () async {
    final note = Note(
      id: 'n',
      title: 'Private plans',
      spaceId: kCryptSpaceId,
      reminderAt: DateTime.now().add(const Duration(days: 1)),
    );
    final state = await boot(AppData(notes: [note], spaces: [], cards: []));
    scheduled.clear();
    state.rescheduleReminders();
    await settle();
    final mine =
        scheduled.where((s) => s['id'] == NotificationService.idFor('n'));
    expect(mine, isNotEmpty);
    expect(mine.single['title'], isNot('Private plans'));
  });

  test('moving a reminded note into the Crypt hides its reminder', () async {
    final note = Note(
      id: 'n',
      title: 'Private plans',
      reminderAt: DateTime.now().add(const Duration(days: 1)),
    );
    final state = await boot(AppData(notes: [note], spaces: [], cards: []));
    await settle();
    scheduled.clear();

    await state.moveNoteToSpace('n', kCryptSpaceId);
    await settle();
    final mine =
        scheduled.where((s) => s['id'] == NotificationService.idFor('n'));
    expect(mine, isNotEmpty);
    expect(mine.last['title'], isNot('Private plans'));
  });
}

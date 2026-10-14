import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/models/impulse.dart';
import 'package:braim/services/calendar_days.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// Progress, streaks and analytics count the same days the heatmap shows.
void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_reflex_counts_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  final states = <AppState>[];
  Future<AppState> boot(List<Impulse> impulses) async {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await StorageService.instance.save(
      AppData(notes: [], spaces: [], cards: [], impulses: impulses),
    );
    final state = AppState();
    states.add(state);
    await state.init();
    return state;
  }

  tearDown(() async {
    for (final s in states) {
      await s.flushNow();
      s.dispose();
    }
    states.clear();
  });

  final today = DateTime.now();
  String key(DateTime d) => AppState.dayKeyFor(d);
  DateTime ago(int n) => addDays(today, -n);

  test('a long-term goal is not complete once its daily reminders are ticked',
      () {
    final reminder = Thread(title: 'Study 1h')..doneDays.add(key(today));
    final goal = Impulse(
      title: 'Degree',
      mode: ImpulseMode.longTerm,
      threads: [reminder],
      sections: [
        Section(title: 'Year 1', subsections: [
          Subsection(title: 'Maths', threads: [Thread(title: 'Exam')]),
        ]),
      ],
    );
    expect(goal.isComplete, isFalse);
  });

  test('analytics leaves out the days before a reflex began', () async {
    final run = Thread(title: 'Run')..doneDays.add(key(today));
    final state = await boot([Impulse(title: 'Running', threads: [run])]);
    final imp = state.impulses.single;
    expect(state.scopeTallyOver([imp], 7), (1, 1));
    expect(state.scopeTallyOver([imp], 365), (1, 1));
  });

  test('a streak follows each task\'s own weekdays', () async {
    final run = Thread(title: 'Run')
      ..doneDays.addAll({key(ago(3)), key(ago(2)), key(ago(1))});
    // Only on the weekday five days ago: never due in the last four days.
    final legs = Thread(title: 'Legs', days: {ago(5).weekday});
    final state = await boot([
      Impulse(
        title: 'Training',
        startDate: ago(10),
        threads: [run, legs],
      ),
    ]);
    final s = state.streakFor(state.impulses.single);
    expect(s.current, 3);
  });

  test('a long-term goal\'s streak counts its nested tasks', () async {
    final exam = Thread(title: 'Revise')
      ..doneDays.addAll({key(ago(2)), key(ago(1))});
    final state = await boot([
      Impulse(
        title: 'Degree',
        mode: ImpulseMode.longTerm,
        startDate: ago(5),
        sections: [
          Section(title: 'Year 1', subsections: [
            Subsection(title: 'Maths', threads: [exam]),
          ]),
        ],
      ),
    ]);
    expect(state.streakFor(state.impulses.single).current, 2);
  });

  test('a checklist streak needs ticks on consecutive days', () async {
    final a = Thread(title: 'Draft')..doneDays.add(key(ago(40)));
    final b = Thread(title: 'Edit')..doneDays.add(key(ago(1)));
    final state = await boot([
      Impulse(
        title: 'Launch',
        mode: ImpulseMode.checklist,
        startDate: ago(50),
        threads: [a, b],
      ),
    ]);
    final s = state.streakFor(state.impulses.single);
    expect(s.best, 1);
    expect(s.current, lessThanOrEqualTo(1));
  });

  test('a task inside a long-term goal can be moved to another reflex',
      () async {
    final task = Thread(title: 'Essay');
    final goal = Impulse(
      title: 'Degree',
      mode: ImpulseMode.longTerm,
      sections: [
        Section(title: 'Year 1', subsections: [
          Subsection(title: 'English', threads: [task]),
        ]),
      ],
    );
    final other = Impulse(title: 'Writing');
    final state = await boot([goal, other]);

    await state.moveThread(goal.id, task.id, other.id);
    expect(state.impulseById(goal.id)!.allThreads, isEmpty);
    expect(state.impulseById(other.id)!.threads.map((t) => t.id), [task.id]);
  });
}

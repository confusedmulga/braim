import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/web/web_events.dart';

/// Stands in for AppState: a revision and a way to notify.
class _Source extends ChangeNotifier {
  int rev = 0;

  void change() {
    rev++;
    notifyListeners();
  }

  void viewOnly() => notifyListeners();

  bool get listened => hasListeners;
}

void main() {
  late _Source source;
  late WebEventHub hub;

  setUp(() {
    source = _Source();
    hub = WebEventHub(source: source, revision: () => source.rev);
  });

  /// Collects the `changed` events a stream delivers.
  List<int> changedRevs(List<String> received) => [
    for (final chunk in received)
      if (chunk.startsWith('event: changed'))
        (jsonDecode(chunk.split('data: ')[1].trim()) as Map)['rev'] as int,
  ];

  test(
    'sends at most one event per 500 ms, and the last change is never lost',
    () {
      fakeAsync((async) {
        final received = <String>[];
        hub.connect('s1').listen((b) => received.add(utf8.decode(b)));
        async.flushMicrotasks();
        expect(received.first, startsWith(': hello'));

        // A storm of ten changes within 100 ms.
        for (var i = 0; i < 10; i++) {
          source.change();
          async.elapse(const Duration(milliseconds: 10));
        }
        expect(changedRevs(received), [1]); // the first goes out at once

        async.elapse(const Duration(milliseconds: 399)); // 499 ms since it
        expect(changedRevs(received), [1]);
        async.elapse(const Duration(milliseconds: 1));
        expect(changedRevs(received), [1, 10]); // the rest, as one event

        // Quiet for a while, then a single change goes out at once.
        async.elapse(const Duration(seconds: 2));
        source.change();
        async.flushMicrotasks();
        expect(changedRevs(received), [1, 10, 11]);
        hub.closeAll();
      });
    },
  );

  test('never faster than one per 500 ms under a steady stream of changes', () {
    fakeAsync((async) {
      final times = <Duration>[];
      final start = async.elapsed;
      hub.connect('s1').listen((b) {
        if (utf8.decode(b).startsWith('event: changed')) {
          times.add(async.elapsed - start);
        }
      });
      for (var i = 0; i < 300; i++) {
        source.change();
        async.elapse(const Duration(milliseconds: 10));
      }
      async.elapse(const Duration(seconds: 1));
      for (var i = 1; i < times.length; i++) {
        expect(
          times[i] - times[i - 1],
          greaterThanOrEqualTo(const Duration(milliseconds: 500)),
        );
      }
      expect(times.length, inInclusiveRange(6, 8)); // about 3 s of changes
      hub.closeAll();
    });
  });

  test('view-only notifications (no new revision) send nothing', () {
    fakeAsync((async) {
      final received = <String>[];
      hub.connect('s1').listen((b) => received.add(utf8.decode(b)));
      source.viewOnly();
      async.elapse(const Duration(seconds: 1));
      expect(changedRevs(received), isEmpty);
      hub.closeAll();
    });
  });

  test('keeps idle streams open with a comment every 25 seconds', () {
    fakeAsync((async) {
      final received = <String>[];
      hub.connect('s1').listen((b) => received.add(utf8.decode(b)));
      async.elapse(const Duration(seconds: 24));
      expect(received.where((c) => c.startsWith(': keep-alive')), isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(received.where((c) => c.startsWith(': keep-alive')), hasLength(1));
      hub.closeAll();
    });
  });

  test('listens to the library only while a stream is open', () async {
    expect(source.listened, isFalse);
    final a = hub.connect('s1').listen((_) {});
    final b = hub.connect('s2').listen((_) {});
    expect(source.listened, isTrue);
    expect(hub.anyConnected, isTrue);

    await a.cancel(); // the browser went away
    expect(source.listened, isTrue);
    await b.cancel();
    expect(hub.anyConnected, isFalse);
    expect(source.listened, isFalse);
  });

  test('closing a session ends only its streams', () async {
    final done = <String>[];
    hub.connect('s1').listen((_) {}, onDone: () => done.add('s1a'));
    hub.connect('s1').listen((_) {}, onDone: () => done.add('s1b'));
    hub.connect('s2').listen((_) {}, onDone: () => done.add('s2'));
    hub.closeSession('s1');
    await pumpEventQueue();
    expect(done, unorderedEquals(['s1a', 's1b']));
    expect(hub.anyConnected, isTrue);
    hub.closeAll();
    await pumpEventQueue();
    expect(done, contains('s2'));
    expect(source.listened, isFalse);
  });
}

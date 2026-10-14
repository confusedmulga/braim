import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/screens/book_screen.dart';
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

/// A book's pages: deleting goes through Recently Deleted, and the Contents
/// screen edits the pages it shows.
void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_book_fixes_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  });

  Future<AppState> boot() async {
    await StorageService.instance.save(
      AppData(notes: const [], spaces: const [], cards: const []),
    );
    final state = AppState();
    await state.init();
    return state;
  }

  test('deleting a page keeps it in Recently Deleted until restored', () async {
    final state = await boot();
    final book = await state.addBook('Ink');
    final chapter = state.bookPages(book.id).last;

    await state.deleteBookPage(chapter.id);
    expect(state.bookPages(book.id).any((p) => p.id == chapter.id), isFalse);
    expect(state.deletedNotes.any((n) => n.id == chapter.id), isTrue);

    await state.restoreNote(chapter.id);
    expect(state.bookPages(book.id).any((p) => p.id == chapter.id), isTrue);
    await state.flushNow();
    state.dispose();
  });

  final navKey = GlobalKey<NavigatorState>();

  /// A fresh book ([Contents, Introduction, Chapter I]) with its Contents
  /// screen open over a blank home.
  Future<(AppState, String)> openContents(WidgetTester tester) async {
    final state = (await tester.runAsync(boot))!;
    final book = (await tester.runAsync(() => state.addBook('Ink')))!;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          navigatorKey: navKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => ContentsScreen(bookId: book.id)),
    );
    await tester.pumpAndSettle();
    return (state, book.id);
  }

  Future<void> close(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    state.dispose();
  }

  testWidgets('Contents reorders the right page when Contents is not first', (
    tester,
  ) async {
    final (state, bookId) = await openContents(tester);
    // Put Chapter I before the Contents page.
    await tester.runAsync(() => state.reorderBookPages(bookId, 2, 0));
    await tester.pumpAndSettle();
    expect(
      state.bookPages(bookId).map((p) => p.title),
      ['Chapter I', 'Contents', 'Introduction'],
    );

    // On the Contents screen: [Chapter I, Introduction]. Drag Chapter I below.
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorder(0, 2);
    await tester.pumpAndSettle();
    final listed = state
        .bookPages(bookId)
        .where((p) => p.title != 'Contents')
        .map((p) => p.title);
    expect(listed, ['Introduction', 'Chapter I']);
    await close(tester, state);
  });

  testWidgets('a title typed on Contents is kept when going back', (
    tester,
  ) async {
    final (state, bookId) = await openContents(tester);
    await tester.enterText(find.byType(TextField).last, 'The Storm');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(state.bookPages(bookId).last.title, 'The Storm');
    await close(tester, state);
  });
}

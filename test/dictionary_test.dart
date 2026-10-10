import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:braim/services/dictionary.dart';

/// The real packed dictionary, read from the asset on disk.
Future<ByteData> _asset() async =>
    ByteData.sublistView(await File(Dictionary.assetPath).readAsBytes());

void main() {
  late Directory root;
  late Dictionary dictionary;

  setUpAll(() {
    sqfliteFfiInit();
    root = Directory.systemTemp.createTempSync('braim_dictionary_test');
    dictionary = Dictionary(
      factory: databaseFactoryFfi,
      directory: () async => root,
      loadAsset: _asset,
    );
  });

  tearDownAll(() async {
    await dictionary.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<String> words(List<DictEntry> entries) =>
      [for (final e in entries) e.word];

  test('unpacks on first use, once, and clears out an older edition',
      () async {
    final dir = Directory('${root.path}/dictionary')..createSync();
    final stale = File('${dir.path}/oewn-2019.db')..writeAsStringSync('old');

    final entries = await dictionary.define('happy');
    expect(words(entries), ['happy']);
    final db = File('${dir.path}/oewn-${Dictionary.edition}.db');
    expect(db.existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);
    expect(File('${db.path}.part').existsSync(), isFalse);

    // Reopened (as on the next app start): read straight from disk.
    final stamp = db.lastModifiedSync();
    final again = Dictionary(
      factory: databaseFactoryFfi,
      directory: () async => root,
      loadAsset: () => fail('should not unpack again'),
    );
    expect(words(await again.define('happy')), ['happy']);
    expect(db.lastModifiedSync(), stamp);
    // (Not closed: both share sqflite's one connection to the file.)
  });

  test('a word: meanings by class, examples and synonyms', () async {
    final happy = (await dictionary.define('happy')).single;
    final (wordClass, senses) = happy.groups.single;
    expect(wordClass, WordClass.adjective);
    expect(senses.first.definition,
        'enjoying or showing or marked by joy or pleasure');
    expect(senses.first.examples, contains('a happy smile'));
    expect(senses.expand((s) => s.synonyms), containsAll(['glad', 'felicitous']));

    // "run" is mostly a verb: its verb meanings come first.
    final run = (await dictionary.define('run')).first;
    expect(run.groups.first.$1, WordClass.verb);
    expect(run.groups.map((g) => g.$1), contains(WordClass.noun));
  });

  test('finds the base form of what was selected', () async {
    // Irregular forms come from the data, regular ones from the endings.
    expect(words(await dictionary.define('went')), ['go']);
    expect(words(await dictionary.define('Mice')), ['mouse']);
    expect(words(await dictionary.define('cities')), ['city']);
    expect(words(await dictionary.define('stopped')), contains('stop'));
    // The word itself first, then its base.
    expect(words(await dictionary.define('“running,”')),
        ['running', 'run']);
    // Phrases are headwords too.
    expect(words(await dictionary.define('ice cream')), ['ice cream']);
    expect(await dictionary.define('qwzxv'), isEmpty);
    expect(await dictionary.define('  ...  '), isEmpty);
  });

  test('one search: definitions, synonyms, and the word for a meaning',
      () async {
    final happy = await dictionary.search('happy');
    expect(words(happy.entries), ['happy']);
    expect(happy.synonyms, containsAll(['glad', 'blissful']));
    expect(happy.synonyms, isNot(contains('happy')));
    expect(happy.startingWith, isEmpty);

    final described = await dictionary.search('fear of great heights');
    expect(described.entries, isEmpty);
    expect(described.byMeaning.first.words, contains('acrophobia'));
    expect(described.byMeaning.first.definition,
        'a morbid fear of great heights');

    // Half typed: the headwords it begins.
    final typing = await dictionary.search('serendip');
    expect(typing.entries, isEmpty);
    expect(typing.startingWith, contains('serendipity'));
  });

  group('text helpers', () {
    test('keyOf trims quotes and punctuation, keeps inner marks', () {
      expect(Dictionary.keyOf('  “Well-being,”  '), 'well-being');
      expect(Dictionary.keyOf("o’clock."), "o'clock");
      expect(Dictionary.keyOf('ice\n cream'), 'ice cream');
    });

    test('canDefine takes a word or a short phrase, not a passage', () {
      expect(Dictionary.canDefine('serendipity'), isTrue);
      expect(Dictionary.canDefine('in the nick of time'), isFalse);
      expect(Dictionary.canDefine('take a nap'), isTrue);
      expect(Dictionary.canDefine('42'), isFalse);
      expect(Dictionary.canDefine('   '), isFalse);
    });

    test('baseForms strips one regular ending', () {
      expect(Dictionary.baseForms('wolves'), contains('wolve'));
      expect(Dictionary.baseForms('bigger'), contains('big'));
      expect(Dictionary.baseForms('cats'), contains('cat'));
      expect(Dictionary.baseForms("cat's"), contains('cat'));
      expect(Dictionary.baseForms('well-being'), contains('well being'));
    });

    test('meaningMatch keeps the content words, the last as a prefix', () {
      expect(Dictionary.meaningMatch('fear of heights'), 'fear heights*');
      expect(Dictionary.meaningMatch('the of a'), isNull);
      expect(Dictionary.meaningMatch('someone who st'), 'someone st');
    });
  });
}

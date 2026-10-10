import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// A word's class, as WordNet tags its meanings.
enum WordClass { noun, verb, adjective, adverb }

/// One meaning of a word.
class DictSense {
  const DictSense({
    required this.definition,
    this.examples = const [],
    this.synonyms = const [],
  });

  final String definition;

  /// Up to two example uses.
  final List<String> examples;

  /// Other words with this same meaning.
  final List<String> synonyms;
}

/// A headword and its meanings, grouped by word class (its main use first).
class DictEntry {
  const DictEntry({required this.word, required this.groups});

  final String word;
  final List<(WordClass, List<DictSense>)> groups;
}

/// A meaning found by searching definitions, and the words that carry it.
class DictMeaning {
  const DictMeaning({
    required this.words,
    required this.wordClass,
    required this.definition,
  });

  final List<String> words;
  final WordClass wordClass;
  final String definition;
}

/// Everything one search bar finds: the query as a word, its synonyms, words
/// whose meaning matches the query, and headwords it starts (while typing).
class DictResults {
  const DictResults({
    this.entries = const [],
    this.synonyms = const [],
    this.byMeaning = const [],
    this.startingWith = const [],
  });

  final List<DictEntry> entries;
  final List<String> synonyms;
  final List<DictMeaning> byMeaning;

  /// Headwords beginning with the query; only filled when it isn't a word.
  final List<String> startingWith;

  bool get isEmpty =>
      entries.isEmpty &&
      synonyms.isEmpty &&
      byMeaning.isEmpty &&
      startingWith.isEmpty;
}

/// The offline English dictionary: Open English WordNet, shipped packed in the
/// app (`assets/dictionary/oewn.db.gz`, built by `tool/build_dictionary.py`)
/// and unpacked to app storage the first time a word is looked up. Nothing
/// leaves the phone; nothing is loaded until the dictionary is first used.
class Dictionary {
  Dictionary({
    DatabaseFactory? factory,
    Future<Directory> Function()? directory,
    Future<ByteData> Function()? loadAsset,
  })  : _factory = factory,
        _directory = directory ?? getApplicationSupportDirectory,
        _loadAsset = loadAsset ?? (() => rootBundle.load(assetPath));

  /// The app's dictionary. Tests swap in one reading the asset from disk.
  static Dictionary instance = Dictionary();

  /// The WordNet edition inside the asset; a new one is unpacked afresh.
  static const edition = '2025';
  static const assetPath = 'assets/dictionary/oewn.db.gz';

  final DatabaseFactory? _factory;
  final Future<Directory> Function() _directory;
  final Future<ByteData> Function() _loadAsset;

  Future<Database>? _db;

  Future<Database> _open() => _db ??= _unpackAndOpen().catchError(
        (Object e) {
          _db = null; // let the next lookup try again
          throw e;
        },
      );

  Future<Database> _unpackAndOpen() async {
    final dir = Directory('${(await _directory()).path}/dictionary');
    final file = File('${dir.path}/oewn-$edition.db');
    if (!await file.exists()) {
      await dir.create(recursive: true);
      // An earlier edition (or a half-written unpack) is no longer needed.
      await for (final old in dir.list()) {
        if (old is File && old.path != file.path) {
          try {
            await old.delete();
          } catch (_) {}
        }
      }
      final packed = await _loadAsset();
      final bytes = packed.buffer
          .asUint8List(packed.offsetInBytes, packed.lengthInBytes);
      final path = file.path;
      await Isolate.run(() => _unpack(bytes, path));
    }
    return (_factory ?? databaseFactory).openDatabase(file.path,
        options: OpenDatabaseOptions(readOnly: true));
  }

  /// Inflates the packed database off the UI thread, writing it under a
  /// temporary name first so a cut-off unpack is never mistaken for a whole.
  static Future<void> _unpack(Uint8List packed, String path) async {
    final part = File('$path.part');
    final sink = part.openWrite();
    await sink.addStream(gzip.decoder.bind(Stream.value(packed)));
    await sink.close();
    await part.rename(path);
  }

  /// Closes the database (tests).
  @visibleForTesting
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }

  // ---- Lookups --------------------------------------------------------------

  /// The entries for a selected word or short phrase: the word itself and its
  /// base form ("running" → running, run; "went" → go), most likely first.
  Future<List<DictEntry>> define(String text, {int limit = 3}) async {
    final key = keyOf(text);
    if (key.isEmpty) return const [];
    final db = await _open();

    // The word as written, any irregular base ("mice" → mouse), then the
    // regular ones guessed by stripping an ending.
    final keys = [key, ...baseForms(key)];
    final found = <int, String>{};
    final rows = await db.query('words',
        columns: ['id', 'lemma', 'key'],
        where: 'key IN (${List.filled(keys.length, '?').join(',')})',
        whereArgs: keys);
    final irregular = await db.rawQuery(
        'SELECT w.id, w.lemma FROM forms f JOIN words w ON w.id = f.word '
        'WHERE f.form = ?',
        [key]);
    for (final r in rows.where((r) => r['key'] == key)) {
      found[r['id'] as int] = r['lemma'] as String;
    }
    for (final r in irregular) {
      found.putIfAbsent(r['id'] as int, () => r['lemma'] as String);
    }
    for (final k in keys.skip(1)) {
      for (final r in rows.where((r) => r['key'] == k)) {
        found.putIfAbsent(r['id'] as int, () => r['lemma'] as String);
      }
    }

    final entries = <DictEntry>[];
    for (final e in found.entries.take(limit)) {
      final entry = await _entry(db, e.key, e.value);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  Future<DictEntry?> _entry(Database db, int wordId, String lemma) async {
    final senses = await db.rawQuery(
        'SELECT s.id, s.pos, s.def, s.ex FROM senses se '
        'JOIN synsets s ON s.id = se.synset WHERE se.word = ? '
        'ORDER BY se.rank',
        [wordId]);
    if (senses.isEmpty) return null;
    final synonyms = await _wordsOf(db, [for (final s in senses) s['id'] as int],
        except: wordId);

    final byClass = <WordClass, List<DictSense>>{};
    for (final s in senses) {
      final ex = s['ex'] as String?;
      byClass.putIfAbsent(_classOf(s['pos'] as String), () => []).add(DictSense(
            definition: s['def'] as String,
            examples: ex == null || ex.isEmpty ? const [] : ex.split('\n'),
            synonyms: _distinct(synonyms[s['id']] ?? const [], lemma, 6),
          ));
    }
    // The class with the most meanings is the word's main use ("run" is a
    // verb before it's a noun); ties keep noun, verb, adjective, adverb.
    final groups = byClass.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) {
        final byCount = b.$2.length.compareTo(a.$2.length);
        return byCount != 0 ? byCount : a.$1.index.compareTo(b.$1.index);
      });
    return DictEntry(word: lemma, groups: groups);
  }

  /// The words carrying each of [synsets], those for whom it's a main meaning
  /// first.
  Future<Map<int, List<String>>> _wordsOf(Database db, List<int> synsets,
      {int? except}) async {
    if (synsets.isEmpty) return const {};
    final rows = await db.rawQuery(
        'SELECT se.synset, w.lemma FROM senses se JOIN words w ON w.id = se.word '
        'WHERE se.synset IN (${List.filled(synsets.length, '?').join(',')}) '
        '${except == null ? '' : 'AND se.word <> $except '}'
        'ORDER BY se.rank, w.lemma',
        synsets);
    final out = <int, List<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r['synset'] as int, () => []).add(r['lemma'] as String);
    }
    return out;
  }

  /// One search bar for everything: [query] as a word (its meanings), its
  /// synonyms, the words whose meaning it describes ("fear of heights" →
  /// acrophobia), and — when it isn't a word yet — headwords it begins.
  Future<DictResults> search(String query) async {
    final key = keyOf(query);
    if (key.isEmpty) return const DictResults();
    final db = await _open();

    final entries = await define(query);
    final headwords = {for (final e in entries) e.word.toLowerCase()};

    // Synonyms: every meaning's fellow words, then (for adjectives) the
    // words of similar meanings ("happy" ~ blissful, glad).
    final synonyms = <String>[];
    void addSynonym(String w) {
      if (synonyms.length < 40 &&
          !headwords.contains(w.toLowerCase()) &&
          !synonyms.any((s) => s.toLowerCase() == w.toLowerCase())) {
        synonyms.add(w);
      }
    }

    for (final e in entries) {
      for (final (_, senses) in e.groups) {
        for (final s in senses) {
          s.synonyms.forEach(addSynonym);
        }
      }
    }
    final ownSynsets = <int>{};
    if (entries.isNotEmpty) {
      final ids = await db.rawQuery(
          'SELECT se.synset FROM senses se JOIN words w ON w.id = se.word '
          'WHERE w.lemma IN (${List.filled(entries.length, '?').join(',')})',
          [for (final e in entries) e.word]);
      ownSynsets.addAll(ids.map((r) => r['synset'] as int));
      final similar = await db.rawQuery(
          'SELECT w.lemma FROM similar si '
          'JOIN senses se ON se.synset = si.other '
          'JOIN words w ON w.id = se.word '
          'WHERE si.synset IN (${List.filled(ownSynsets.length, '?').join(',')}) '
          'ORDER BY se.rank, w.lemma',
          ownSynsets.toList());
      for (final r in similar) {
        addSynonym(r['lemma'] as String);
      }
    }

    final byMeaning = await _byMeaning(db, query, skip: ownSynsets);

    var startingWith = const <String>[];
    if (entries.isEmpty && key.length >= 2) {
      final rows = await db.rawQuery(
          'SELECT DISTINCT lemma FROM words WHERE key >= ? AND key < ? '
          'ORDER BY length(key), key LIMIT 12',
          [key, '$key￿']);
      startingWith = [for (final r in rows) r['lemma'] as String];
    }

    return DictResults(
      entries: entries,
      synonyms: synonyms,
      byMeaning: byMeaning,
      startingWith: startingWith,
    );
  }

  /// Whether this SQLite has FTS4 for the definitions index. Every Android
  /// build does; where one doesn't (some desktop builds), a plain scan does.
  bool? _hasFts;

  /// Meanings whose definition holds every content word of [query] (Porter
  /// stemmed, so "heights" finds "height"), tightest definitions first.
  Future<List<DictMeaning>> _byMeaning(Database db, String query,
      {Set<int> skip = const {}}) async {
    final terms = meaningWords(query);
    if (terms.isEmpty) return const [];
    List<Map<String, Object?>>? rows;
    if (_hasFts != false) {
      try {
        rows = await db.rawQuery(
            'SELECT s.id, s.pos, s.def FROM defs '
            'JOIN synsets s ON s.id = defs.docid '
            'WHERE defs MATCH ? ORDER BY length(s.def) LIMIT 40',
            [meaningMatch(query)]);
        _hasFts = true;
      } on DatabaseException catch (e) {
        if (!'$e'.contains('no such module')) rethrow;
        _hasFts = false;
      }
    }
    rows ??= await db.rawQuery(
        'SELECT id, pos, def FROM synsets '
        'WHERE ${List.filled(terms.length, 'def LIKE ?').join(' AND ')} '
        'ORDER BY length(def) LIMIT 40',
        [for (final t in terms) '%$t%']);
    final hits = rows.where((r) => !skip.contains(r['id'])).take(20).toList();
    final words = await _wordsOf(db, [for (final r in hits) r['id'] as int]);
    return [
      for (final r in hits)
        if (words[r['id']] case final w? when w.isNotEmpty)
          DictMeaning(
            words: _distinct(w, null, 4),
            wordClass: _classOf(r['pos'] as String),
            definition: r['def'] as String,
          ),
    ];
  }

  // ---- Text helpers ---------------------------------------------------------

  /// [raw] as a lookup key: curly apostrophes straightened, spaces collapsed,
  /// punctuation and quotes trimmed from both ends, lower case.
  static String keyOf(String raw) => raw
      .replaceAll(RegExp('[‘’ʼ]'), "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '')
      .toLowerCase();

  /// Whether [text] is worth offering to look up: a word or a short phrase.
  static bool canDefine(String text) {
    final t = text.trim();
    return t.isNotEmpty &&
        t.length <= 60 &&
        t.split(RegExp(r'\s+')).length <= 4 &&
        RegExp(r'\p{L}', unicode: true).hasMatch(t);
  }

  /// WordNet's regular endings ("morphy"): strip one, maybe restore a letter.
  static const _endings = [
    ('s', ''), ('ses', 's'), ('xes', 'x'), ('zes', 'z'), ('ches', 'ch'),
    ('shes', 'sh'), ('men', 'man'), ('ies', 'y'), // nouns
    ('es', 'e'), ('es', ''), ('ed', 'e'), ('ed', ''), ('ing', 'e'),
    ('ing', ''), // verbs
    ('er', ''), ('est', ''), ('er', 'e'), ('est', 'e'), // adjectives
  ];

  /// Guesses at the base form of [key] ("stopped" → stop, "cities" → city),
  /// for checking against the headwords. Irregular forms come from the
  /// database instead.
  static List<String> baseForms(String key) {
    final out = <String>[];
    void add(String s) {
      if (s.length > 1 && s != key && !out.contains(s)) out.add(s);
    }

    if (key.endsWith("'s")) add(key.substring(0, key.length - 2));
    if (key.endsWith("s'")) add(key.substring(0, key.length - 1));
    for (final (suffix, ending) in _endings) {
      if (key.length <= suffix.length + 1 || !key.endsWith(suffix)) continue;
      final stem = key.substring(0, key.length - suffix.length);
      add(stem + ending);
      // A doubled final consonant: "stopped" → stop, "bigger" → big.
      final n = stem.length;
      if (ending.isEmpty &&
          n > 2 &&
          stem[n - 1] == stem[n - 2] &&
          !'aeiouyls'.contains(stem[n - 1])) {
        add(stem.substring(0, n - 1));
      }
    }
    if (key.contains('-')) add(key.replaceAll('-', ' '));
    if (key.contains(' ')) add(key.replaceAll(' ', '-'));
    return out;
  }

  /// Words too common to say anything about a meaning.
  static const _stopWords = {
    'a', 'an', 'the', 'of', 'to', 'in', 'on', 'for', 'with', 'by', 'at',
    'from', 'or', 'and', 'as', 'is', 'are', 'be', 'that', 'this', 'it',
    'its', 'into', 'who', 'which', 'what', 'when', 'where', 'how', 'not',
  };

  /// The words of [query] that say something about a meaning (letters and
  /// digits only, so they are safe in any query).
  static List<String> meaningWords(String query) => query
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.length > 1 && !_stopWords.contains(w))
      .toList();

  /// The full-text query for finding a word by its meaning: every content
  /// word of [query] must appear; the last may still be half typed. Null when
  /// nothing is left to search for.
  static String? meaningMatch(String query) {
    final words = meaningWords(query);
    if (words.isEmpty) return null;
    final last = words.removeLast();
    return [...words, last.length >= 3 ? '$last*' : last].join(' ');
  }

  static WordClass _classOf(String pos) => switch (pos) {
        'v' => WordClass.verb,
        'a' => WordClass.adjective,
        'r' => WordClass.adverb,
        _ => WordClass.noun,
      };

  /// [words] without repeats (ignoring case) or [skip], at most [max].
  static List<String> _distinct(List<String> words, String? skip, int max) {
    final seen = <String>{if (skip != null) skip.toLowerCase()};
    final out = <String>[];
    for (final w in words) {
      if (out.length >= max) break;
      if (seen.add(w.toLowerCase())) out.add(w);
    }
    return out;
  }
}

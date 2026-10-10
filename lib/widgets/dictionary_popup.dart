import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/dictionary.dart';
import '../theme/app_theme.dart';

/// Shows what [text] means in a small card over the page; a tap outside
/// closes it. Tapping a synonym looks that word up in the same card.
Future<void> showDefinition(BuildContext context, String text) =>
    _showPopup(context, _DefinitionCard(text: text));

/// The dictionary's own search: one field for a word's meanings, its
/// synonyms, and the word for a described meaning, each in its own group.
Future<void> showDictionarySearch(BuildContext context, {String initial = ''}) =>
    _showPopup(context, _DictionarySearch(initial: initial));

Future<void> _showPopup(BuildContext context, Widget child) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => child,
      transitionBuilder: (_, animation, _, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );

/// [items] with a Define button after Copy, when [selected] is a word or a
/// short phrase. Define opens the meaning card from [context], which must
/// outlive the menu (the page's own context, not the menu's).
List<ContextMenuButtonItem> withDefine(
  BuildContext context,
  List<ContextMenuButtonItem> items,
  String selected,
  VoidCallback hideMenu,
) {
  if (!Dictionary.canDefine(selected)) return items;
  final define = ContextMenuButtonItem(
    label: context.t.define,
    onPressed: () {
      showDefinition(context, selected);
      hideMenu();
    },
  );
  final out = List.of(items);
  final copy = out.indexWhere((i) => i.type == ContextMenuButtonType.copy);
  out.insert(copy + 1, define);
  return out;
}

/// A text field's usual selection menu, plus Define for a selected word.
Widget definableFieldMenu(BuildContext context, EditableTextState field) {
  final value = field.textEditingValue;
  final selected =
      value.selection.isValid ? value.selection.textInside(value.text) : '';
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: field.contextMenuAnchors,
    buttonItems: withDefine(Navigator.of(context).context,
        field.contextMenuButtonItems, selected, field.hideToolbar),
  );
}

/// A [SelectionArea] whose menu also offers Define for a selected word.
class DefinableSelectionArea extends StatefulWidget {
  const DefinableSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  State<DefinableSelectionArea> createState() => _DefinableSelectionAreaState();
}

class _DefinableSelectionAreaState extends State<DefinableSelectionArea> {
  String _selected = '';

  @override
  Widget build(BuildContext context) => SelectionArea(
        onSelectionChanged: (content) => _selected = content?.plainText ?? '',
        contextMenuBuilder: (_, region) =>
            AdaptiveTextSelectionToolbar.buttonItems(
          anchors: region.contextMenuAnchors,
          buttonItems: withDefine(context, region.contextMenuButtonItems,
              _selected, region.hideToolbar),
        ),
        child: widget.child,
      );
}

// ---- The meaning card --------------------------------------------------------

class _DefinitionCard extends StatefulWidget {
  const _DefinitionCard({required this.text});

  final String text;

  @override
  State<_DefinitionCard> createState() => _DefinitionCardState();
}

class _DefinitionCardState extends State<_DefinitionCard> {
  /// The words looked up in this card, so a synonym can be stepped back from.
  final _trail = <String>[];
  late Future<List<DictEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _go(widget.text);
  }

  void _go(String word) {
    _trail.add(word);
    _entries = Dictionary.instance.define(word);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: 440, maxHeight: size.height * 0.6),
          child: _Card(
            child: FutureBuilder<List<DictEntry>>(
              future: _entries,
              builder: (context, snap) {
                final word = _trail.last;
                final header = _CardHeader(
                  title: snap.data?.firstOrNull?.word ?? Dictionary.keyOf(word),
                  onBack: _trail.length > 1
                      ? () => setState(() {
                            _trail.removeLast();
                            _entries = Dictionary.instance.define(_trail.last);
                          })
                      : null,
                  onOpenDictionary: () {
                    // The card closes; the search opens from the page below.
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    showDictionarySearch(navigator.context, initial: word);
                  },
                );
                final Widget body;
                if (snap.hasError) {
                  body = _Note(context.t.dictionaryOpenFailed);
                } else if (!snap.hasData) {
                  body = const _Loading();
                } else if (snap.data!.isEmpty) {
                  body = _Note(context.t.dictionaryNotFound(word.trim()));
                } else {
                  final entries = snap.data!;
                  body = Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      children: [
                        for (var i = 0; i < entries.length; i++)
                          _EntryView(
                            key: ValueKey('${entries[i].word}#$i'),
                            entry: entries[i],
                            showWord: i > 0,
                            onWord: (w) => setState(() => _go(w)),
                          ),
                      ],
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, body],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: AppPalette.sheet,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppPalette.cardOutline),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.title,
    required this.onBack,
    required this.onOpenDictionary,
  });

  final String title;
  final VoidCallback? onBack;
  final VoidCallback onOpenDictionary;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(onBack == null ? 20 : 6, 10, 6, 6),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                tooltip: context.t.back,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: onBack,
              ),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: kNoteHeadingFont,
                  fontSize: 24,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.inkPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: context.t.dictionary,
              icon: Icon(Icons.manage_search_rounded,
                  color: AppPalette.inkSecondary),
              onPressed: onOpenDictionary,
            ),
          ],
        ),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 26),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        child: Text(text,
            style: TextStyle(
                fontSize: 14.5, height: 1.4, color: AppPalette.inkSecondary)),
      );
}

String _className(BuildContext context, WordClass c) => switch (c) {
      WordClass.noun => context.t.wordClassNoun,
      WordClass.verb => context.t.wordClassVerb,
      WordClass.adjective => context.t.wordClassAdjective,
      WordClass.adverb => context.t.wordClassAdverb,
    };

/// One headword's meanings, by word class. A long list (a word like "run"
/// has dozens) shows the first few of each class until asked for all.
class _EntryView extends StatefulWidget {
  const _EntryView({
    super.key,
    required this.entry,
    required this.onWord,
    this.showWord = false,
  });

  final DictEntry entry;
  final ValueChanged<String> onWord;

  /// Set the headword above the meanings (the card's header already shows
  /// the first one).
  final bool showWord;

  @override
  State<_EntryView> createState() => _EntryViewState();
}

class _EntryViewState extends State<_EntryView> {
  static const _preview = 4;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final total = entry.groups.fold<int>(0, (n, g) => n + g.$2.length);
    final hidden = _all
        ? 0
        : entry.groups.fold<int>(
            0, (n, g) => n + (g.$2.length - _preview).clamp(0, 1 << 20));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showWord)
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 2),
            child: Text(
              entry.word,
              style: TextStyle(
                fontFamily: kNoteHeadingFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppPalette.inkPrimary,
              ),
            ),
          ),
        for (final (wordClass, senses) in entry.groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              _className(context, wordClass),
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: AppPalette.scheme.primary,
              ),
            ),
          ),
          for (var i = 0; i < senses.length && (_all || i < _preview); i++)
            _SenseView(
                number: i + 1, sense: senses[i], onWord: widget.onWord),
        ],
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _all = true),
              child: Text(context.t.dictionaryShowAll(total)),
            ),
          ),
      ],
    );
  }
}

class _SenseView extends StatelessWidget {
  const _SenseView({
    required this.number,
    required this.sense,
    required this.onWord,
  });

  final int number;
  final DictSense sense;
  final ValueChanged<String> onWord;

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.inkPrimary;
    final soft = AppPalette.inkSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text('$number.',
                style: TextStyle(
                    fontSize: 15, height: 1.4, fontWeight: FontWeight.w700,
                    color: soft)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sense.definition,
                    style: TextStyle(fontSize: 15, height: 1.4, color: ink)),
                for (final ex in sense.examples)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('“$ex”',
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            fontStyle: FontStyle.italic,
                            color: soft)),
                  ),
                if (sense.synonyms.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _WordChips(
                        words: sense.synonyms, onWord: onWord, dense: true),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable words: a synonym, a suggestion. Tapping one looks it up.
class _WordChips extends StatelessWidget {
  const _WordChips({
    required this.words,
    required this.onWord,
    this.dense = false,
  });

  final List<String> words;
  final ValueChanged<String> onWord;
  final bool dense;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final w in words)
            Material(
              color: AppPalette.chipFill,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onWord(w),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: dense ? 9 : 12, vertical: dense ? 4 : 7),
                  child: Text(w,
                      style: TextStyle(
                          fontSize: dense ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.inkPrimary)),
                ),
              ),
            ),
        ],
      );
}

// ---- The search popup ---------------------------------------------------------

class _DictionarySearch extends StatefulWidget {
  const _DictionarySearch({required this.initial});

  final String initial;

  @override
  State<_DictionarySearch> createState() => _DictionarySearchState();
}

class _DictionarySearchState extends State<_DictionarySearch> {
  late final _field = TextEditingController(text: widget.initial);
  final _scroll = ScrollController();
  Timer? _debounce;
  int _run = 0;
  bool _busy = false;
  bool _failed = false;
  DictResults _results = const DictResults();

  /// The query [_results] answer, so a stale answer is never shown.
  String _shown = '';

  @override
  void initState() {
    super.initState();
    if (widget.initial.trim().isNotEmpty) _search(widget.initial);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => _search(text));
    setState(() {}); // the clear button
  }

  Future<void> _search(String text) async {
    final run = ++_run;
    if (text.trim().isEmpty) {
      setState(() {
        _results = const DictResults();
        _shown = '';
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final results = await Dictionary.instance.search(text);
      if (!mounted || run != _run) return;
      // New results start from the top.
      if (text.trim() != _shown && _scroll.hasClients) _scroll.jumpTo(0);
      setState(() {
        _results = results;
        _shown = text.trim();
        _busy = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || run != _run) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  /// A word tapped in the results becomes the search.
  void _lookUp(String word) {
    _debounce?.cancel();
    _field.value = TextEditingValue(
        text: word, selection: TextSelection.collapsed(offset: word.length));
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _search(word);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          12, media.padding.top + 12, 12, media.viewInsets.bottom + 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 22, color: AppPalette.inkSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _field,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: _onChanged,
                          onSubmitted: _search,
                          style: TextStyle(
                              fontSize: 17, color: AppPalette.inkPrimary),
                          decoration: InputDecoration(
                            hintText: t.dictionarySearchHint,
                            hintStyle:
                                TextStyle(color: AppPalette.inkSecondary),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_field.text.isNotEmpty)
                        IconButton(
                          tooltip: t.clearSearch,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _field.clear();
                            _onChanged('');
                          },
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppPalette.cardOutline),
                Flexible(child: _resultsView(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultsView(BuildContext context) {
    final t = context.t;
    if (_failed) return _Note(t.dictionaryOpenFailed);
    if (_shown.isEmpty) {
      return _busy ? const _Loading() : _Note(t.dictionaryIntro);
    }
    final r = _results;
    if (r.isEmpty) return _Note(t.dictionaryNoResults);
    return ListView(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      children: [
        if (r.entries.isNotEmpty) ...[
          _SectionTitle(t.dictionaryDefinitions),
          for (var i = 0; i < r.entries.length; i++)
            _EntryView(
              key: ValueKey('$_shown#${r.entries[i].word}#$i'),
              entry: r.entries[i],
              showWord: true,
              onWord: _lookUp,
            ),
        ],
        if (r.synonyms.isNotEmpty) ...[
          _SectionTitle(t.dictionarySynonyms),
          _WordChips(words: r.synonyms, onWord: _lookUp),
        ],
        if (r.startingWith.isNotEmpty) ...[
          _SectionTitle(t.dictionaryStartingWith(_shown)),
          _WordChips(words: r.startingWith, onWord: _lookUp),
        ],
        if (r.byMeaning.isNotEmpty) ...[
          _SectionTitle(t.dictionaryByMeaning),
          for (final m in r.byMeaning)
            _MeaningTile(meaning: m, onWord: _lookUp),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text(
            t.dictionarySource,
            style: TextStyle(
                fontSize: 11.5,
                color: AppPalette.inkSecondary.withValues(alpha: 0.8)),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 0.9,
            fontWeight: FontWeight.w700,
            color: AppPalette.inkSecondary,
          ),
        ),
      );
}

/// A meaning found by its description: its words (tap to look one up), then
/// the definition.
class _MeaningTile extends StatelessWidget {
  const _MeaningTile({required this.meaning, required this.onWord});

  final DictMeaning meaning;
  final ValueChanged<String> onWord;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onWord(meaning.words.first),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: meaning.words.join(', '),
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary),
                  ),
                  TextSpan(
                    text: '  ${_className(context, meaning.wordClass)}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        color: AppPalette.scheme.primary),
                  ),
                ]),
              ),
              const SizedBox(height: 2),
              Text(meaning.definition,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: AppPalette.inkSecondary)),
            ],
          ),
        ),
      );
}

import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rotating Home-feed greetings (one is picked at random per session).
const List<String> kHomeGreetings = [
  'Back again.',
  'You again.',
  'Scrolling through old thoughts?',
  'Somewhere in here, a decent idea.',
  'The notes remember more than you do.',
  'Another day, another fragment.',
  'Proof you think a lot.',
  'Half-written thoughts, fully committed.',
  "Yesterday's urgent idea, today's mystery.",
  'You wrote this. No context given.',
  'Some of these were 2 AM decisions.',
  "Feed's fresh. Thoughts, less so.",
  'Every note was a small emergency at the time.',
  'Still not sure what half of these mean.',
  'Nothing gold stays unwritten around here.',
  "The notes don't judge. Much.",
  'Note count: rising.',
  'Late-night thought dump?',
  'Caught another one before it got away.',
  'Thinking again?',
  'Not all of these aged well.',
  'Somewhere between profound and grocery lists.',
  'Second brain, occasionally right.',
  'Infinite scroll, finite thoughts.',
  "A feed only you'll fully understand.",
  'Externalized memory, mildly chaotic.',
  'This is what offloading your brain looks like.',
  'The pile grows.',
  'Back to see what past-you was thinking.',
  'Same brain, new scroll.',
  'A little strange, reading yourself back.',
  'Half your personality lives in this feed.',
  'A record of you, in fragments.',
  'Fragments today, maybe a pattern eventually.',
  'Powered by caffeine and vague ambition.',
  'Somewhere in here: a shopping list disguised as a manifesto.',
  'Beep. New scroll detected. Proceed with thoughts.',
];

/// Rotating greetings for the Narrative (books) tab, every book-flavoured
/// line from the original Narrative set.
const List<String> kNarrativeGreetings = [
  "The book's still there. Waiting, not judging.",
  'Pick up where the last chapter left off.',
  'A blank page or an old one. Your call.',
  'Somewhere, a half-written book wants attention.',
  'The blank page again. It never gets less blank.',
  "Pages don't fill themselves. Rude, really.",
  'Progress, saved. Pick it back up.',
  'The story continues where you left it.',
  'New book, old book, pick a battle.',
  'Chapter one or chapter thirty. Both start the same way.',
  'A chapter for the ages.',
  'Write small or write big. Both count.',
  'Words, any format.',
  'Short and honest, or long and ambitious.',
  'Hemingway apparently wrote drunk. You can write however.',
  "Shakespeare didn't have a notes app. Unfair advantage, really.",
  'Your future biographer will want the details.',
  'The manuscript missed you.',
  'Back to the book.',
  'The plot thickens. Or it will, once you write it.',
  "Word count doesn't move on its own.",
  'Every finished book was once this exact mess.',
  "Chapter's not going to end itself.",
  'Draft now, cringe later, edit eventually.',
  'First drafts are legally allowed to be bad.',
  'The book exists in your head. Get it out.',
  'One paragraph today still counts as writing a book.',
  'Nobody writes chapter twelve without writing chapter eleven.',
  'The characters have been waiting. Some are annoyed.',
  'Where you left off is still where you left off.',
  'Still unfinished. Still fixable.',
  'Books get written in exactly these moments.',
  'Add a sentence. Call it momentum.',
  'Your book, mid-existence.',
  'Somewhere between idea and ISBN.',
  "Tolstoy took six years. You've got time.",
  'Write badly. Editing exists for a reason.',
  "The ending's already decided. It's just waiting for the middle.",
  'Blank chapter or messy chapter = messy wins.',
  'Future readers, currently unaware.',
  "It's not procrastination if you open the draft.",
  "The book won't know you were gone.",
  'Pick a chapter. Any chapter.',
  'Author mode.',
  'Writing a book is just typing with commitment.',
  'Every great novel is 90% sitting back down.',
  'The draft forgives everything except absence.',
];

/// Rotating greetings for the Journal tab — lines that fit a feed where the
/// day's tasks and the day's journal live side by side.
const List<String> kJournalGreetings = [
  'What got done, and what you felt about it.',
  'The to-do list and the diary, finally in one room.',
  'Half productivity, half confession.',
  'Checkboxes and feelings, side by side.',
  'What happened, and what you did about it.',
  "Tasks lie about being finished. Journals don't.",
  'The list says what to do. The entry says how it went.',
  'Some days you check boxes. Some days you just survive them.',
  'Progress and processing, same screen.',
  'What you did today, and what you thought about it.',
  'The plan and the reality, sitting next to each other.',
  'Ticked boxes, untidy thoughts.',
  'One column for doing, one for dealing.',
  "Today's tasks. Today's mess. Both valid.",
  'Where the schedule meets the aftermath.',
  'Structure on one side, chaos on the other. Balanced, technically.',
  'What needed doing, what actually happened.',
  'Accountability and honesty, sharing a screen.',
  'The list keeps you moving. The journal keeps you honest.',
  'Some tasks get done. Some just get written about instead.',
  'Executive function and emotional processing, cohabiting peacefully.',
  'Half planner, half therapist.',
  'Where "done" and "how are you, really" coexist.',
  'efficiency and reflection. pick your poison.',
  'Today, itemized and narrated.',
];

/// Rotating greetings for the Sparks (cards) tab — the saved-links pile.
const List<String> kCardsGreetings = [
  "Links you swore you'd get to.",
  "Screenshot culture's more organized cousin.",
  "The internet's leftovers, plated nicely.",
  'Half these got saved out of guilt.',
  'Bookmarking: the illusion of future productivity.',
  "Someone's Wednesday thought, now permanently yours.",
  'A shrine to "I\'ll circle back to this."',
  'Tabs, but they finally learned to behave.',
  "This is where curiosity goes when it's too tired to click immediately.",
  "You didn't read it. You archived the intention to.",
  "Every link here made a promise it didn't keep yet.",
  'The read-later pile, now with receipts.',
  'Digital hoarding, but make it aesthetic.',
  'Not procrastination. Research infrastructure.',
  'Somewhere between "saved" and "sacred."',
  'The stuff you liked enough to trap.',
  'Links that outlived the group chat that sent them.',
  'Your taste, indexed without your permission.',
  'A little museum of things you found mildly compelling.',
  'Where "interesting" goes to wait its turn.',
  'This is basically a personality test made of URLs.',
  "Nobody reads these immediately. That's the deal.",
  'Saved with intent. Opened with hesitation.',
  "Preview mode: because commitment's a lot to ask.",
  'A quiet flex of everything you almost read.',
  'The margin notes are doing more work than the article.',
  "Half link dump, half diary you didn't mean to write.",
  'Some of these you saved just to feel informed.',
  'You clicked save like it counted as reading.',
  'Cool people hoard links too. This is fine.',
];

/// Rotating greetings for the Cortex (folders/folds) tab — the place where
/// notes, sparks and links get organized into folds.
const List<String> kCortexGreetings = [
  'Where the chaos finally gets a cortex.',
  'Everything you own, technically organized.',
  "The folds remember. You mostly don't.",
  'Structure, imposed after the fact.',
  'Some folds have a system. Others are just a mood.',
  'This is where chaos goes to pretend it has order.',
  'Filed away, not necessarily found again.',
  'A folder for everything, and everything eventually in the wrong folder.',
  'Your brain, but with labels.',
  "The folds don't judge your naming conventions. Much.",
  "Everything's in here somewhere. Good luck.",
  'Order, loosely defined.',
  'Some folds are archives. Some are just where things went to hide.',
  'You built this system. You also forgot half of it.',
  'Not mess. Just... unindexed potential.',
  'A filing cabinet that occasionally reflects reality.',
  "Folds within folds within a decision you don't remember making.",
  'This is organization. Allegedly.',
  'Everything sorted, nothing forgotten. Mostly true.',
  'Where notes, sparks, and links pretend to get along.',
  "The folds hold it together so you don't have to.",
  'A structure that made sense at 1 AM.',
  'Cortex: because "everything, everywhere" needed a folder system.',
  "Some folds are load-bearing. Don't touch those.",
  "This is what a second brain's filing cabinet looks like.",
  'Organized enough to feel in control. Barely.',
  "The folds know where everything is. You're just visiting.",
  'A little architecture for a lot of thoughts.',
  'Some folds are curated. Some are just where things landed.',
  "Everything has a place. Whether it's the right one is unclear.",
  "The system works. Don't ask too many questions.",
];

/// Shown on Home only while the library is still empty (a brand-new user): a
/// gentle nudge to write the very first note. Never shown once a note exists.
const List<String> kFirstNoteGreetings = [
  'Your first note starts here.',
  'A fresh mind, an empty page.',
  'Give that first thought a home.',
  'One tap on the pencil, and you begin.',
  'Every second brain starts with one note.',
];

// Each feed's greeting is chosen once per app session and cached here, so
// scrolling — which can remount the header in a lazy feed — never reshuffles
// the line. A caller that passes its own [random] bypasses the cache (tests).
final Map<String, String> _greetingCache = {};

String _cachedGreeting(String key, List<String> pool, Random? random) {
  if (random != null) return pool[random.nextInt(pool.length)];
  return _greetingCache[key] ??= pool[Random().nextInt(pool.length)];
}

String pickFirstNoteGreeting({Random? random}) =>
    _cachedGreeting('first', kFirstNoteGreetings, random);

/// Picks the Home greeting: in the first half-hour of the small hours
/// (1:00–1:30, 2:00–2:30 … 5:00–5:30) the matching night line always wins;
/// otherwise one of the regular lines. Chosen once per session (see cache).
String pickHomeGreeting({Random? random, DateTime? now}) {
  String compute(DateTime t) {
    if (t.hour >= 1 && t.hour <= 5 && t.minute < 30) {
      return 'Where ${t.hour} AM ideas meet ${t.hour} PM confusion.';
    }
    return kHomeGreetings[(random ?? Random()).nextInt(kHomeGreetings.length)];
  }

  if (random != null || now != null) return compute(now ?? DateTime.now());
  return _greetingCache['home'] ??= compute(DateTime.now());
}

String pickNarrativeGreeting({Random? random}) =>
    _cachedGreeting('narrative', kNarrativeGreetings, random);

String pickJournalGreeting({Random? random}) =>
    _cachedGreeting('journal', kJournalGreetings, random);

String pickCardsGreeting({Random? random}) =>
    _cachedGreeting('cards', kCardsGreetings, random);

String pickCortexGreeting({Random? random}) =>
    _cachedGreeting('cortex', kCortexGreetings, random);

/// The big display text that opens every feed (in place of the old title
/// header). The line is chosen once per mount, so it changes per app open,
/// not per scroll.
class FeedGreeting extends StatefulWidget {
  const FeedGreeting({super.key, this.text, this.picker});

  /// Fixed text (Cards/Cortex), or null to use [picker].
  final String? text;
  final String Function()? picker;

  @override
  State<FeedGreeting> createState() => _FeedGreetingState();
}

class _FeedGreetingState extends State<FeedGreeting> {
  late final String _line = widget.text ?? widget.picker!();

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'Lora',
      fontSize: 40,
      height: 1.08,
      color: AppPalette.inkPrimary,
    );
    final bold = base.copyWith(fontWeight: FontWeight.w700);

    return Padding(
      // Clears the fixed top bar (menu + search + sort + account), which
      // sits at safe-area top + 8 and is 50 tall, then leaves a gap before
      // the greeting so the welcome line never hides under the bar.
      padding: EdgeInsets.fromLTRB(
          6, MediaQuery.of(context).padding.top + 78, 6, 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The first (visual) line is bold, the rest regular. Lay the whole
          // paragraph out in bold and read the real first-line break from
          // its line metrics, the first line is fully bold when rendered,
          // so its wrap point matches this measurement exactly.
          final tp = TextPainter(
            text: TextSpan(text: _line, style: bold),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);
          var split = _line.length;
          final lines = tp.computeLineMetrics();
          if (lines.length > 1) {
            final first = lines.first;
            split = tp
                .getPositionForOffset(
                    Offset(first.width, first.height / 2))
                .offset;
          }
          tp.dispose();
          return Text.rich(
            TextSpan(children: [
              TextSpan(text: _line.substring(0, split), style: bold),
              TextSpan(text: _line.substring(split), style: base),
            ]),
          );
        },
      ),
    );
  }
}

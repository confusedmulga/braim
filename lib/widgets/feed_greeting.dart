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
];

/// Rotating greetings for the Journal tab, every diary-flavoured line.
const List<String> kJournalGreetings = [
  'Dear diary, but make it dignified.',
  'Today happened. Want proof?',
  "Whatever's rattling around, it goes here.",
  'The day, unfiltered.',
  "Get it down before someone else's version wins.",
  'One honest sentence beats zero.',
  'Future you will want the details.',
  'Something happened today. Probably worth a line.',
  "Today's thoughts, before they go.",
  'A page for today.',
  'New page, old page, blank page, take your pick.',
  'Diary entry or literary legacy, no wrong answer.',
];

const String kCardsGreeting = 'Where saved links stop being lost links.';
const String kCortexGreeting = 'Where the chaos finally gets a cortex.';

/// Shown on Home only while the library is still empty (a brand-new user): a
/// gentle nudge to write the very first note. Never shown once a note exists.
const List<String> kFirstNoteGreetings = [
  'Your first note starts here.',
  'A fresh mind, an empty page.',
  'Give that first thought a home.',
  'One tap on the pencil, and you begin.',
  'Every second brain starts with one note.',
];

String pickFirstNoteGreeting({Random? random}) {
  final r = random ?? Random();
  return kFirstNoteGreetings[r.nextInt(kFirstNoteGreetings.length)];
}

/// Picks the Home greeting: in the first half-hour of the small hours
/// (1:00–1:30, 2:00–2:30 … 5:00–5:30) the matching night line always wins;
/// otherwise one of the regular lines.
String pickHomeGreeting({Random? random, DateTime? now}) {
  final t = now ?? DateTime.now();
  if (t.hour >= 1 && t.hour <= 5 && t.minute < 30) {
    return 'Where ${t.hour} AM ideas meet ${t.hour} PM confusion.';
  }
  final r = random ?? Random();
  return kHomeGreetings[r.nextInt(kHomeGreetings.length)];
}

String pickNarrativeGreeting({Random? random}) {
  final r = random ?? Random();
  return kNarrativeGreetings[r.nextInt(kNarrativeGreetings.length)];
}

String pickJournalGreeting({Random? random}) {
  final r = random ?? Random();
  return kJournalGreetings[r.nextInt(kJournalGreetings.length)];
}

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

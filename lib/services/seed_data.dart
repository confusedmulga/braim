import '../models/book.dart';
import '../models/note.dart';
import '../models/note_block.dart';
import '../models/space.dart';
import '../models/tweet_card.dart';

/// A ready-made library, a spread of notes, saved cards and a short book -
/// used to fill a fresh install so every feature can be tried at once. It's
/// pure data (no bundled images) so it loads instantly and offline, and it
/// stays in the project so the app can be reseeded any time (handy after an
/// emulator wipes its storage).
class SeedBundle {
  const SeedBundle({
    required this.spaces,
    required this.notes,
    required this.cards,
    required this.books,
  });

  final List<Space> spaces;
  final List<Note> notes;
  final List<TweetCard> cards;
  final List<Book> books;
}

class SeedData {
  const SeedData._();

  /// Builds a fresh copy of the demo library. New ids are minted on every
  /// call, so loading it twice simply adds a second, independent copy rather
  /// than clashing with the first.
  static SeedBundle build() {
    final now = DateTime.now();
    DateTime ago(Duration d) => now.subtract(d);
    String two(int n) => n.toString().padLeft(2, '0');
    String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
    String day(Duration back) => ymd(now.subtract(back));

    NoteBlock text(String body) => NoteBlock(type: NoteBlockType.text, text: body);

    // ---- Folders -----------------------------------------------------------
    final ideas = Space(
        name: 'Ideas',
        colorValue: 0xFFE6D3FF, // lilac
        createdAt: ago(const Duration(days: 30)));
    final recipes = Space(
        name: 'Recipes',
        colorValue: 0xFFBFEAD6, // mint
        createdAt: ago(const Duration(days: 21)));
    final work = Space(
        name: 'Work',
        colorValue: 0xFFC9E4FF, // sky
        createdAt: ago(const Duration(days: 14)));
    final spaces = [ideas, recipes, work];

    // ---- Notes -------------------------------------------------------------
    final notes = <Note>[
      // A pinned welcome note (plain text).
      Note(
        title: 'Welcome to Braim ✨',
        blocks: [
          text(
            "This is a demo library so you can poke around every corner.\n\n"
            "• Home holds your notes, long-press to select several.\n"
            "• Cards keeps links you share in.\n"
            "• Journal, Cortex and the Crypt are one swipe away.\n"
            "• Link anything, tap [[Tide clock app]], [[Lemon pasta]] or the "
            "[[Habits worth stealing]] card.\n\n"
            "Delete all of this whenever you like from Settings › Clear all data.",
          ),
        ],
        tags: ['start'],
        pinned: true,
        createdAt: ago(const Duration(days: 1)),
        updatedAt: ago(const Duration(hours: 2)),
      ),

      // A tagged idea, filed in a folder.
      Note(
        title: 'Tide clock app',
        blocks: [
          text(
            'A single dial that shows the tide instead of the time. '
            'Rising on the left, ebbing on the right, a little boat that '
            'drifts with it. Pull data from the NOAA station nearest you.',
          ),
        ],
        spaceId: ideas.id,
        tags: ['idea', 'someday'],
        colorValue: 0xFFE8F0FE,
        createdAt: ago(const Duration(days: 3)),
        updatedAt: ago(const Duration(days: 3)),
      ),

      // A checklist-style note with a colour.
      Note(
        title: 'Groceries',
        blocks: [
          text('- Oat milk\n- Sourdough\n- Lemons (x4)\n- Parmesan\n- Basil\n- Coffee beans'),
        ],
        tags: ['errand'],
        colorValue: 0xFFFFF3C4,
        createdAt: ago(const Duration(days: 2)),
        updatedAt: ago(const Duration(hours: 20)),
      ),

      // A reminder / task, due soon.
      Note(
        title: 'Call the dentist',
        blocks: [text('Ask about the 9am slot on Thursday and whether the cleaning is covered.')],
        tags: ['todo'],
        reminderAt: now.add(const Duration(hours: 3)),
        createdAt: ago(const Duration(hours: 6)),
        updatedAt: ago(const Duration(hours: 6)),
      ),

      // A second reminder, further out.
      Note(
        title: 'Water the plants',
        blocks: [text('The fern by the window is thirsty. Fig tree every other day.')],
        tags: ['home', 'todo'],
        reminderAt: now.add(const Duration(days: 1, hours: 2)),
        createdAt: ago(const Duration(days: 1, hours: 4)),
        updatedAt: ago(const Duration(days: 1, hours: 4)),
      ),

      // A note that embeds a link card between text blocks.
      Note(
        title: 'Read later',
        blocks: [
          text('Bookmarking this to come back to when I have a quiet hour:'),
          NoteBlock(
            type: NoteBlockType.link,
            url: 'https://www.calnewport.com/books/deep-work/',
            linkTitle: 'Deep Work, Cal Newport',
            linkSite: 'calnewport.com',
            linkFetched: true,
          ),
          text('The bit about scheduling every minute of the day is worth trying for a week.'),
        ],
        tags: ['reading'],
        createdAt: ago(const Duration(days: 5)),
        updatedAt: ago(const Duration(days: 5)),
      ),

      // A recipe, filed in a folder.
      Note(
        title: 'Lemon pasta',
        blocks: [
          text(
            'Serves 2, ready in 15 minutes.\n\n'
            '1. Boil spaghetti in well-salted water.\n'
            '2. Whisk zest + juice of 1 lemon with a handful of parmesan and a '
            'ladle of pasta water into a loose cream.\n'
            '3. Toss the drained pasta through it off the heat. Pepper, basil, done.',
          ),
        ],
        spaceId: recipes.id,
        tags: ['dinner'],
        createdAt: ago(const Duration(days: 8)),
        updatedAt: ago(const Duration(days: 8)),
      ),

      // A short reflective note.
      Note(
        title: 'On slow mornings',
        blocks: [
          text(
            'The best hour of my day is the one nobody knows about.\n\n'
            'Before the phone lights up, before the first message lands, there '
            'is a stretch of quiet that belongs entirely to me. I make coffee '
            'slowly. I read something on paper. I let the day arrive instead of '
            'chasing it.\n\n'
            'It took me years to protect that hour, and it will take the rest of '
            'my life to keep it. But a morning spent gently is a day spent well.',
          ),
        ],
        tags: ['writing'],
        createdAt: ago(const Duration(days: 6)),
        updatedAt: ago(const Duration(days: 6)),
      ),

      // Work note, filed in a folder.
      Note(
        title: 'Sprint retro, what stuck',
        blocks: [
          text(
            'Keep: shorter standups, pairing on the tricky migration.\n'
            'Drop: the Friday deploy freeze, it just moved the rush to Monday.\n'
            'Try: a shared "surprises" doc so nobody debugs the same trap twice.',
          ),
        ],
        spaceId: work.id,
        tags: ['work'],
        createdAt: ago(const Duration(days: 4)),
        updatedAt: ago(const Duration(days: 4)),
      ),

      // An archived note (lives in Archive, not the feed).
      Note(
        title: 'Old meeting notes',
        blocks: [text('Q2 planning, superseded by the new roadmap. Kept for reference.')],
        archived: true,
        createdAt: ago(const Duration(days: 40)),
        updatedAt: ago(const Duration(days: 39)),
      ),

      // A note in the trash (Recently deleted).
      Note(
        title: 'Scratch',
        blocks: [text('asdf testing testing, safe to leave in the bin.')],
        deletedAt: ago(const Duration(days: 2)),
        createdAt: ago(const Duration(days: 3)),
        updatedAt: ago(const Duration(days: 2, hours: 12)),
      ),

      // ---- Journal entries (show only in the Journal tab) ------------------
      Note(
        journalDate: day(Duration.zero),
        blocks: [
          text(
            "Loaded the demo library to give the app a proper shake-down. "
            "Everything's in here now, folders, reminders, a little book. "
            "Felt good to see it full instead of empty.",
          ),
        ],
        createdAt: ago(const Duration(hours: 1)),
        updatedAt: ago(const Duration(hours: 1)),
      ),
      Note(
        journalDate: day(const Duration(days: 1)),
        blocks: [
          text(
            'Rainy one. Stayed in, cooked the lemon pasta again, read two '
            'chapters. The quiet kind of day I never regret.',
          ),
        ],
        createdAt: ago(const Duration(days: 1)),
        updatedAt: ago(const Duration(days: 1)),
      ),
      Note(
        journalDate: day(const Duration(days: 9)),
        blocks: [
          text(
            'Long walk by the water at dusk. Kept thinking about that tide-clock '
            'idea. Some ideas only arrive when you stop reaching for them.',
          ),
        ],
        createdAt: ago(const Duration(days: 9)),
        updatedAt: ago(const Duration(days: 9)),
      ),
      // "On this day": entries on today's date in earlier years.
      Note(
        journalDate: ymd(DateTime(now.year - 1, now.month, now.day)),
        blocks: [
          text(
            'A year ago today. Signed the lease on the little flat by the '
            'harbour. Terrified and thrilled in equal measure.',
          ),
        ],
        createdAt: DateTime(now.year - 1, now.month, now.day, 21, 10),
        updatedAt: DateTime(now.year - 1, now.month, now.day, 21, 10),
      ),
      Note(
        journalDate: ymd(DateTime(now.year - 2, now.month, now.day)),
        blocks: [
          text(
            'Two years ago today. First morning of the new job. Wore the good '
            'shoes, got the bus early, needn’t have worried at all.',
          ),
        ],
        createdAt: DateTime(now.year - 2, now.month, now.day, 8, 5),
        updatedAt: DateTime(now.year - 2, now.month, now.day, 8, 5),
      ),
    ];

    // ---- Saved cards (links) ----------------------------------------------
    NoteBlock cardText(String body) =>
        NoteBlock(type: NoteBlockType.text, text: body);

    final cards = <TweetCard>[
      TweetCard(
        url: 'https://www.paulgraham.com/greatwork.html',
        siteName: 'paulgraham.com',
        authorName: 'Paul Graham',
        text: 'How to Do Great Work, a long essay on choosing what to work on and sticking with it.',
        fetched: true,
        pinned: true,
        articleText:
            "If you collected lists of techniques for doing great work in a lot "
            "of different fields, what would the intersection look like? I decided "
            "to find out.\n\n"
            "The first step is to decide what to work on. The work you choose "
            "needs to have three qualities: it has to be something you have a "
            "natural aptitude for, that you have a deep interest in, and that "
            "offers scope to do great work.\n\n"
            "Four steps: choose a field, learn enough to get to the frontier, "
            "notice gaps, explore promising ones. This is how practically "
            "everyone who's done great work has done it.",
        createdAt: ago(const Duration(days: 2)),
        updatedAt: ago(const Duration(days: 2)),
      ),
      TweetCard(
        url: 'https://waitbutwhy.com/2018/04/picking-career.html',
        siteName: 'Wait But Why',
        authorName: 'Tim Urban',
        text: 'How to Pick a Career (That Actually Fits You)',
        fetched: true,
        articleText:
            "We tend to think our career path is a straight line, but it's really "
            "a series of experiments. The trick is to run more of them, and to run "
            "them faster.\n\n"
            "Your career is the roughly 20,000 to 150,000 working hours you'll "
            "spend during your life. Spending a few dozen of them thinking hard "
            "about how to spend the rest is time well spent.",
        createdAt: ago(const Duration(days: 4)),
        updatedAt: ago(const Duration(days: 4)),
      ),
      TweetCard(
        url: 'https://en.wikipedia.org/wiki/Cassini%E2%80%93Huygens',
        siteName: 'Wikipedia',
        text: 'Cassini–Huygens, the twenty-year mission to Saturn and its moons.',
        fetched: true,
        articleText:
            "Cassini–Huygens was a space-research mission by NASA, ESA and the "
            "Italian Space Agency to study Saturn and its system, including its "
            "rings and natural satellites.\n\n"
            "Launched in 1997, it reached Saturn in 2004 and studied the planet "
            "until 2017, when it was deliberately flown into Saturn's atmosphere "
            "to protect the potentially habitable moons Enceladus and Titan.",
        createdAt: ago(const Duration(days: 7)),
        updatedAt: ago(const Duration(days: 7)),
      ),
      TweetCard(
        url: 'https://x.com/naval/status/1002103360646823936',
        authorName: 'Naval',
        authorHandle: '@naval',
        text: 'Seek wealth, not money or status. Wealth is having assets that earn while you sleep.',
        fetched: true,
        createdAt: ago(const Duration(days: 10)),
        updatedAt: ago(const Duration(days: 10)),
      ),
      // A card the user titled and annotated, filed in the Work folder.
      TweetCard(
        url: 'https://jamesclear.com/atomic-habits',
        siteName: 'jamesclear.com',
        authorName: 'James Clear',
        text: 'Atomic Habits, tiny changes, remarkable results.',
        noteTitle: 'Habits worth stealing',
        blocks: [
          cardText('Two ideas I keep coming back to: make it obvious, make it easy. '
              'The two-minute rule is the one that actually changed my mornings. '
              'Pairs well with [[On slow mornings]].'),
        ],
        spaceId: work.id,
        fetched: true,
        articleText:
            "You do not rise to the level of your goals. You fall to the level of "
            "your systems. Habits are the compound interest of self-improvement.\n\n"
            "The four laws: make it obvious, make it attractive, make it easy, and "
            "make it satisfying. Invert them to break a bad habit.",
        createdAt: ago(const Duration(days: 12)),
        updatedAt: ago(const Duration(days: 1)),
      ),
    ];

    // ---- A short book ------------------------------------------------------
    final book = Book(
      title: 'The Lantern in the Fog',
      author: 'Maya Ellison',
      description:
          'A short seaside tale in two chapters, a keeper’s daughter, a light '
          'that will not stay lit, and the night the fog spoke back.',
      fontFamily: 'Merriweather',
      createdAt: ago(const Duration(days: 15)),
      updatedAt: ago(const Duration(days: 1)),
    );

    Note page(String kind, String pageTitle, int order,
            {String body = '', String status = '', int target = 0}) =>
        Note(
          title: pageTitle,
          bookId: book.id,
          bookPageKind: kind,
          bookOrder: order,
          bookStatus: status,
          targetWords: target,
          blocks: body.isEmpty ? [] : [text(body)],
          createdAt: ago(const Duration(days: 15)),
          updatedAt: ago(const Duration(days: 2)),
        );

    final bookPages = <Note>[
      page(BookPageKind.contents, 'Contents', 0),
      page(
        BookPageKind.intro,
        'Introduction',
        1,
        body:
            'This is a small story about a lighthouse that stopped working the '
            'winter the fog rolled in and would not leave. It is about the girl '
            'who kept it, and what she heard when the light went dark. Read it '
            'slowly; there is not much of it, and it likes the quiet.',
      ),
      page(
        BookPageKind.chapter,
        'Chapter I, The Keeper’s Daughter',
        2,
        status: BookPageStatus.finished,
        target: 500,
        body:
            'Nora had trimmed the wick every evening since she was nine, which '
            'was the winter her father’s hands began to shake. The lamp was a '
            'living thing to her: it drank oil, it breathed light, and on the '
            'worst nights it sulked.\n\n'
            'The village below called their lighthouse the Lantern, as though it '
            'were a single candle a giant might carry down to the water. From the '
            'gallery Nora could see the whole curve of the coast, the boats '
            'coming home like slow moths, and beyond them the grey wall of the sea.\n\n'
            'On the first night of the fog she climbed the stairs as always, lit '
            'the lamp as always, and watched the beam swallowed whole three feet '
            'past the glass. It was the first time the light had ever failed to '
            'reach the water.',
      ),
      page(
        BookPageKind.chapter,
        'Chapter II, When the Fog Spoke',
        3,
        status: BookPageStatus.draft,
        target: 500,
        body:
            'By the fourth night the fog had a texture to it, wool pulled thin, '
            'and Nora had stopped expecting the beam to cut through. She kept it '
            'burning anyway. A keeper keeps.\n\n'
            'It was near midnight when she heard her name, not shouted, not '
            'urgent, but said, the way you say a word you have been holding a '
            'long time. It came from the seaward side, where there was nothing '
            'but the drop and the water and the endless soft grey.\n\n'
            '“Nora,” the fog said again, and this time she did not tell herself '
            'it was the wind. She set down the oil can, and she went to the rail, '
            'and she answered.',
      ),
    ];

    return SeedBundle(
      spaces: spaces,
      notes: [...notes, ...bookPages],
      cards: cards,
      books: [book],
    );
  }
}

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A book: a bound collection of pages (a Contents, an Introduction, and
/// chapters). The pages themselves are ordinary [Note]s tagged with this
/// book's id, so they reuse the whole note editor, autosave and sync; the
/// Book record just holds the cover, title and typeface.
class Book {
  Book({
    String? id,
    this.title = '',
    this.author = '',
    this.description = '',
    this.coverPath,
    this.fontFamily = 'Lora',
    this.archived = false,
    this.deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  String title;

  /// Whose name goes on the cover. Defaults to the signed-in account the
  /// first time the book is opened, but the writer can change it (pen names,
  /// co-authors, and so on).
  String author;

  /// The blurb shown under the cover when the book is opened.
  String description;

  /// Absolute path to the cover image, or null for a plain gradient cover.
  String? coverPath;

  /// The face the book's pages are typeset in.
  String fontFamily;

  bool archived;
  DateTime? deletedAt;

  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (author.isNotEmpty) 'author': author,
        if (description.isNotEmpty) 'description': description,
        if (coverPath != null) 'coverPath': coverPath,
        'fontFamily': fontFamily,
        'archived': archived,
        'deletedAt': deletedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String?,
        title: (json['title'] as String?) ?? '',
        author: (json['author'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        coverPath: json['coverPath'] as String?,
        fontFamily: (json['fontFamily'] as String?) ?? 'Lora',
        archived: (json['archived'] as bool?) ?? false,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}

/// The kinds of page a book holds.
class BookPageKind {
  static const contents = 'contents';
  static const intro = 'intro';
  static const chapter = 'chapter';

  /// Front/back matter: short set pieces that frame the manuscript.
  static const dedication = 'dedication';
  static const epigraph = 'epigraph';
  static const acknowledgements = 'acknowledgements';

  /// A workshop note attached to a book (a character sketch, a plot idea) —
  /// kept out of the manuscript: it never appears in the Contents, the reader
  /// or an export, and doesn't count toward the book's page or word totals.
  static const note = 'note';

  /// The front/back-matter kinds offered when adding a page.
  static const matter = [dedication, epigraph, acknowledgements];

  /// A short, centred set piece (dedication/epigraph) reads better without a
  /// big chapter heading over it.
  static bool isQuietMatter(String kind) =>
      kind == dedication || kind == epigraph;
}

/// The typefaces a book can be set in. The first three are serif faces made
/// for long-form reading; the last two match the rest of the app.
class BookFonts {
  const BookFonts._();

  static const all = <String>[
    'Lora',
    'EB Garamond',
    'Merriweather',
    'SpaceGrotesk',
    'Caveat',
  ];

  /// A human-friendly label for the font picker (the family names are already
  /// readable except for the compact one).
  static String label(String family) =>
      family == 'SpaceGrotesk' ? 'Space Grotesk' : family;

  /// The bundled (regular, bold) TTF asset paths for a family, so an export
  /// can embed the very face the book is written in. Falls back to Lora.
  static (String regular, String bold) assets(String family) =>
      switch (family) {
        'EB Garamond' => (
            'assets/fonts/EBGaramond-Regular.ttf',
            'assets/fonts/EBGaramond-Bold.ttf'
          ),
        'Merriweather' => (
            'assets/fonts/Merriweather-Regular.ttf',
            'assets/fonts/Merriweather-Bold.ttf'
          ),
        'SpaceGrotesk' => (
            'assets/fonts/SpaceGrotesk-Regular.ttf',
            'assets/fonts/SpaceGrotesk-Bold.ttf'
          ),
        'Caveat' => (
            'assets/fonts/Caveat-Regular.ttf',
            'assets/fonts/Caveat-Bold.ttf'
          ),
        _ => ('assets/fonts/Lora-Regular.ttf', 'assets/fonts/Lora-Bold.ttf'),
      };
}

/// How finished a chapter is; shown as a small tag beside it.
class BookPageStatus {
  static const none = '';
  static const draft = 'draft';
  static const revised = 'revised';
  static const finished = 'final';

  static const all = [none, draft, revised, finished];
}

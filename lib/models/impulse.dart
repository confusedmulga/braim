import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// How an Impulse's Threads behave.
class ImpulseMode {
  /// The same Threads recur every day: they reset each morning and the
  /// progress bar shows *today's* completion.
  static const daily = 'daily';

  /// Threads are one-time milestones: tick them off for good and the bar
  /// fills toward 100% overall.
  static const checklist = 'checklist';

  /// A long-term goal (e.g. a degree): a tree of [Section]s (years) →
  /// [Subsection]s (subjects) → threads, plus a flat "daily reminder" list (the
  /// impulse's own [Impulse.threads]) for anything outside the curriculum.
  static const longTerm = 'longTerm';

  static const all = [daily, checklist, longTerm];
}

/// A Thread's priority flag — a coloured tag shown in lists and its sheet.
class TaskFlag {
  static const none = '';
  static const important = 'important'; // red
  static const best = 'best'; // green
  static const optional = 'optional'; // yellow

  /// The selectable flags, in display order.
  static const all = [important, best, optional];

  /// Sort priority: important first, unflagged last.
  static int rank(String flag) {
    switch (flag) {
      case important:
        return 0;
      case best:
        return 1;
      case optional:
        return 2;
      default:
        return 3;
    }
  }
}

/// A link attached to a Thread — a label and a URL, opened externally.
class TaskLink {
  TaskLink({required this.label, required this.url});
  String label;
  String url;

  Map<String, dynamic> toJson() => {'label': label, 'url': url};

  factory TaskLink.fromJson(Map<String, dynamic> json) => TaskLink(
        label: (json['label'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
      );
}

/// A single tickable subtask inside an Impulse.
class Thread {
  Thread({
    String? id,
    this.title = '',
    this.description = '',
    this.flag = TaskFlag.none,
    Set<String>? doneDays,
    Set<int>? days,
    this.once = false,
    this.reminderMinutes,
    this.endMinutes,
    this.notify = false,
    List<TaskLink>? links,
    this.location = '',
    this.startDate,
    this.deadline,
  })  : id = id ?? _uuid.v4(),
        doneDays = doneDays ?? {},
        days = days ?? {},
        links = links ?? [];

  final String id;
  String title;

  /// A longer note shown on the task's detail sheet.
  String description;

  /// Priority flag: one of [TaskFlag] (empty for none). A coloured chip in
  /// lists.
  String flag;

  /// The set of days ('yyyy-MM-dd') this Thread was completed on — its per-day
  /// history. In [ImpulseMode.daily] it counts as done for a given day only
  /// when that day is present (so it resets each morning while the record
  /// stays); in [ImpulseMode.checklist] any day present means done for good.
  Set<String> doneDays;

  /// The weekdays (1 = Mon … 7 = Sun) this thread runs on. Empty = every day.
  /// Ignored when [once] is set.
  Set<int> days;

  /// A one-time task: it never resets with the day. Ticking it marks it done
  /// for good (like a checklist milestone) and it stays in the list, struck
  /// through, until deleted. Mutually exclusive with weekday recurrence.
  bool once;

  /// Minutes past midnight for the task's start time, plus an optional end time.
  /// Null means unscheduled.
  int? reminderMinutes;
  int? endMinutes;

  /// Whether a notification fires at the start time (only offered once a start
  /// time is set).
  bool notify;

  /// Attached links (label + url) and an optional address that opens in the
  /// device's maps app.
  List<TaskLink> links;
  String location;

  /// Optional calendar dates for a long-term task: when to begin and when it is
  /// due. These are whole dates, distinct from [reminderMinutes]/[endMinutes]
  /// (which are times of day within a single day).
  DateTime? startDate;
  DateTime? deadline;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        if (flag.isNotEmpty) 'flag': flag,
        if (doneDays.isNotEmpty) 'doneDays': (doneDays.toList()..sort()),
        if (days.isNotEmpty) 'days': (days.toList()..sort()),
        if (once) 'once': true,
        if (reminderMinutes != null) 'reminderMinutes': reminderMinutes,
        if (endMinutes != null) 'endMinutes': endMinutes,
        if (notify) 'notify': true,
        if (links.isNotEmpty) 'links': links.map((l) => l.toJson()).toList(),
        if (location.isNotEmpty) 'location': location,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (deadline != null) 'deadline': deadline!.toIso8601String(),
      };

  factory Thread.fromJson(Map<String, dynamic> json) {
    // Migrate the old single 'doneDate' into the per-day history set.
    final days = <String>{
      for (final e in (json['doneDays'] as List?) ?? const []) e.toString(),
    };
    final legacy = json['doneDate'] as String?;
    if (legacy != null && legacy.isNotEmpty) days.add(legacy);
    // Migrate the old `important` bool into the priority flag.
    var flag = (json['flag'] as String?) ?? TaskFlag.none;
    if (flag.isEmpty && ((json['important'] as bool?) ?? false)) {
      flag = TaskFlag.important;
    }
    return Thread(
      id: json['id'] as String?,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      flag: flag,
      doneDays: days,
      days: ((json['days'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toSet(),
      once: (json['once'] as bool?) ?? false,
      reminderMinutes: (json['reminderMinutes'] as num?)?.toInt(),
      endMinutes: (json['endMinutes'] as num?)?.toInt(),
      notify: (json['notify'] as bool?) ?? false,
      links: [
        for (final e in (json['links'] as List?) ?? const [])
          TaskLink.fromJson(e as Map<String, dynamic>),
      ],
      location: (json['location'] as String?) ?? '',
      startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
      deadline: DateTime.tryParse(json['deadline'] as String? ?? ''),
    );
  }
}

/// A subsection inside a long-term impulse's section — e.g. a subject under a
/// year. Holds its own daily tasks / study schedule threads.
class Subsection {
  Subsection({
    String? id,
    this.title = '',
    this.collapsed = false,
    List<Thread>? threads,
  })  : id = id ?? _uuid.v4(),
        threads = threads ?? [];

  final String id;
  String title;

  /// Dropdown state — persisted so it reopens where you left it.
  bool collapsed;
  List<Thread> threads;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (collapsed) 'collapsed': true,
        'threads': threads.map((t) => t.toJson()).toList(),
      };

  factory Subsection.fromJson(Map<String, dynamic> json) => Subsection(
        id: json['id'] as String?,
        title: (json['title'] as String?) ?? '',
        collapsed: (json['collapsed'] as bool?) ?? false,
        threads: ((json['threads'] as List?) ?? const [])
            .map((e) => Thread.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A top-level section inside a long-term impulse — e.g. a year of a degree.
/// Holds subsections (subjects).
class Section {
  Section({
    String? id,
    this.title = '',
    this.collapsed = false,
    List<Subsection>? subsections,
    this.startDate,
    this.deadline,
  })  : id = id ?? _uuid.v4(),
        subsections = subsections ?? [];

  final String id;
  String title;
  bool collapsed;
  List<Subsection> subsections;

  /// Optional span for this section (e.g. a year of a degree).
  DateTime? startDate;
  DateTime? deadline;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (collapsed) 'collapsed': true,
        'subsections': subsections.map((s) => s.toJson()).toList(),
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (deadline != null) 'deadline': deadline!.toIso8601String(),
      };

  factory Section.fromJson(Map<String, dynamic> json) => Section(
        id: json['id'] as String?,
        title: (json['title'] as String?) ?? '',
        collapsed: (json['collapsed'] as bool?) ?? false,
        subsections: ((json['subsections'] as List?) ?? const [])
            .map((e) => Subsection.fromJson(e as Map<String, dynamic>))
            .toList(),
        startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
        deadline: DateTime.tryParse(json['deadline'] as String? ?? ''),
      );
}

/// A project ("Impulse") in the Reflexes section: a giant task made of Threads,
/// with a goal, a deadline and the days of the week you mean to work on it.
class Impulse {
  Impulse({
    String? id,
    this.title = '',
    this.goal = '',
    this.startDate,
    this.deadline,
    this.mode = ImpulseMode.daily,
    this.category = '',
    Set<int>? days,
    List<Thread>? threads,
    List<Section>? sections,
    this.dailyReminderTitle = '',
    this.colorValue,
    this.paused = false,
    this.completedAt,
    this.archived = false,
    this.deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        days = days ?? {},
        threads = threads ?? [],
        sections = sections ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  String title;

  /// What you're setting out to achieve.
  String goal;

  /// When work on the project begins. Falls back to [createdAt] where a start
  /// is needed (e.g. the consistency heatmap's first day).
  DateTime? startDate;

  /// When the project should be finished.
  DateTime? deadline;

  /// The first day of the consistency window: the explicit [startDate] if set,
  /// otherwise the day the impulse was created (date only).
  DateTime get consistencyStart {
    final s = startDate ?? createdAt;
    return DateTime(s.year, s.month, s.day);
  }

  /// [ImpulseMode.daily] or [ImpulseMode.checklist].
  String mode;

  /// A free-form grouping label (e.g. "Work", "Personal") used by the category
  /// tabs above the reflex list. Empty = uncategorised.
  String category;

  /// Consistency: the weekdays (1 = Mon … 7 = Sun) you intend to work on it.
  Set<int> days;

  List<Thread> threads;

  /// Long-term goals only: the curriculum tree (years → subjects). The flat
  /// [threads] above double as this goal's "daily reminder" list.
  List<Section> sections;

  /// The renameable label for a long-term goal's daily-reminder list (its flat
  /// [threads]). Empty falls back to a localized default in the UI.
  String dailyReminderTitle;

  /// A colour tag (a NoteColors swatch ARGB int), for visual coding in the
  /// reflex list. Null = no colour.
  int? colorValue;

  /// On hold: kept in the list but greyed out with a "Paused" badge.
  bool paused;

  /// Set when the user marks the impulse complete by hand (e.g. finished early,
  /// before the deadline). Overrides the computed completion.
  DateTime? completedAt;

  bool archived;
  DateTime? deletedAt;

  final DateTime createdAt;
  DateTime updatedAt;

  bool get isDaily => mode == ImpulseMode.daily;
  bool get isLongTerm => mode == ImpulseMode.longTerm;
  int get totalThreads => threads.length;
  bool get isCompletedManually => completedAt != null;

  /// Every thread in this impulse — the flat daily-reminder list plus all the
  /// curriculum threads nested in sections/subsections.
  List<Thread> get allThreads => [
        ...threads,
        for (final s in sections)
          for (final sub in s.subsections) ...sub.threads,
      ];

  /// Finds a thread by id anywhere in the impulse (flat or nested).
  Thread? findThread(String id) {
    for (final t in allThreads) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Replaces a thread in place wherever it lives. Returns false if not found.
  bool replaceThread(Thread t) {
    for (var i = 0; i < threads.length; i++) {
      if (threads[i].id == t.id) {
        threads[i] = t;
        return true;
      }
    }
    for (final s in sections) {
      for (final sub in s.subsections) {
        for (var i = 0; i < sub.threads.length; i++) {
          if (sub.threads[i].id == t.id) {
            sub.threads[i] = t;
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Removes a thread by id wherever it lives. Returns false if not found.
  bool removeThread(String id) {
    final before = threads.length;
    threads.removeWhere((t) => t.id == id);
    if (threads.length != before) return true;
    for (final s in sections) {
      for (final sub in s.subsections) {
        final b = sub.threads.length;
        sub.threads.removeWhere((t) => t.id == id);
        if (sub.threads.length != b) return true;
      }
    }
    return false;
  }

  /// A weekday (1 = Mon … 7 = Sun) you mean to work on this. With no
  /// consistency days set, every day counts.
  bool scheduledOn(int weekday) => days.isEmpty || days.contains(weekday);

  /// Whether every thread was ticked on [dayKey] — a "complete" day.
  bool allDoneOn(String dayKey) =>
      threads.isNotEmpty && threads.every((t) => t.doneDays.contains(dayKey));

  /// Whether [t] counts as done on [dayKey] ('yyyy-MM-dd'). Daily and long-term
  /// threads are per-day; a checklist thread — or any one-time [Thread.once]
  /// task — is done for good once ticked.
  bool threadDone(Thread t, String dayKey) => t.once
      ? t.doneDays.isNotEmpty
      : (isDaily || isLongTerm)
          ? t.doneDays.contains(dayKey)
          : t.doneDays.isNotEmpty;

  int doneCount(String dayKey) =>
      threads.where((t) => threadDone(t, dayKey)).length;

  /// 0–1 completion (for a given day if daily, overall for a checklist).
  double progress(String dayKey) =>
      threads.isEmpty ? 0 : doneCount(dayKey) / threads.length;

  bool get isComplete =>
      completedAt != null ||
      (threads.isNotEmpty &&
          !isDaily &&
          threads.every((t) => t.doneDays.isNotEmpty));

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (goal.isNotEmpty) 'goal': goal,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (deadline != null) 'deadline': deadline!.toIso8601String(),
        'mode': mode,
        if (category.isNotEmpty) 'category': category,
        'days': days.toList()..sort(),
        'threads': threads.map((t) => t.toJson()).toList(),
        if (sections.isNotEmpty)
          'sections': sections.map((s) => s.toJson()).toList(),
        if (dailyReminderTitle.isNotEmpty)
          'dailyReminderTitle': dailyReminderTitle,
        if (colorValue != null) 'colorValue': colorValue,
        if (paused) 'paused': true,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'archived': archived,
        'deletedAt': deletedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Impulse.fromJson(Map<String, dynamic> json) => Impulse(
        id: json['id'] as String?,
        title: (json['title'] as String?) ?? '',
        goal: (json['goal'] as String?) ?? '',
        startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
        deadline: DateTime.tryParse(json['deadline'] as String? ?? ''),
        mode: (json['mode'] as String?) ?? ImpulseMode.daily,
        category: (json['category'] as String?) ?? '',
        days: ((json['days'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toSet(),
        threads: ((json['threads'] as List?) ?? const [])
            .map((e) => Thread.fromJson(e as Map<String, dynamic>))
            .toList(),
        sections: ((json['sections'] as List?) ?? const [])
            .map((e) => Section.fromJson(e as Map<String, dynamic>))
            .toList(),
        dailyReminderTitle: (json['dailyReminderTitle'] as String?) ?? '',
        colorValue: (json['colorValue'] as num?)?.toInt(),
        paused: (json['paused'] as bool?) ?? false,
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
        archived: (json['archived'] as bool?) ?? false,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}

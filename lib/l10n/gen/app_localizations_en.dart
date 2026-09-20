// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Braim';

  @override
  String get tabHome => 'Home';

  @override
  String get tabCards => 'Sparks';

  @override
  String get tabJournal => 'Journal';

  @override
  String get tabNarrative => 'Narrative';

  @override
  String get tabCortex => 'Cortex';

  @override
  String get navEntries => 'Entries';

  @override
  String get subtitleHome => 'Your nodes';

  @override
  String get subtitleCards => 'Tweets & links you saved';

  @override
  String get subtitleJournal => 'One day at a time';

  @override
  String get subtitleCortex => 'Folds for nodes & sparks';

  @override
  String get searchHint => 'Search nodes, sparks, cortex';

  @override
  String get menu => 'Menu';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get addTag => 'Add tag';

  @override
  String get tagLabel => 'Tag';

  @override
  String get tagHint => 'idea, todo, work';

  @override
  String get reminder => 'Reminder';

  @override
  String get reminderChange => 'Change reminder';

  @override
  String get reminderClear => 'Clear reminder';

  @override
  String get notifPermNeeded => 'Turn on notifications to get reminders.';

  @override
  String get testNotification => 'Test notifications';

  @override
  String get testNotificationSubtitle =>
      'Send one now and one in 10 seconds to check they reach you';

  @override
  String get notifBlocked =>
      'Notifications are off for Braim. Turn them on in system settings.';

  @override
  String get notifTestSent =>
      'Sent one now and scheduled one for 10 seconds. If nothing appears, notifications are blocked in system settings.';

  @override
  String get notifExactOff =>
      'Sent, but exact alarms are off — scheduled reminders can arrive late. Allow \"Alarms & reminders\" for Braim in system settings.';

  @override
  String get delete => 'Delete';

  @override
  String get restore => 'Restore';

  @override
  String get open => 'Open';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String get hideFromFeed => 'Hide from feeds';

  @override
  String get showInFeed => 'Show in feeds';

  @override
  String get hideFromFeedSubtitle =>
      'Keep this fold\'s notes and sparks out of Home and Sparks; they show only inside the fold';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get getStarted => 'Get started';

  @override
  String get empty => 'Empty';

  @override
  String get newNote => 'New node';

  @override
  String get newMarkdown => 'New markdown';

  @override
  String get importFile => 'Import file';

  @override
  String get exportAsPdf => 'Export as PDF';

  @override
  String get exportFailed => 'Couldn\'t export the PDF';

  @override
  String get shareFailed => 'Couldn\'t share the note';

  @override
  String get youtubeDescription => 'Description';

  @override
  String get youtubeTranscript => 'Transcript';

  @override
  String get youtubeFetching => 'Fetching video details…';

  @override
  String get youtubeUnavailable => 'No description or transcript available';

  @override
  String get retry => 'Retry';

  @override
  String get markdownHint => 'Write or paste Markdown…';

  @override
  String get preview => 'Preview';

  @override
  String get saveALink => 'Save a link';

  @override
  String get newFolder => 'New fold';

  @override
  String get newEntry => 'New entry';

  @override
  String get sectionEntries => 'ENTRIES';

  @override
  String get sectionYears => 'YEARS';

  @override
  String get noEntriesForDay => 'Nothing written this day';

  @override
  String get noEntriesThisMonth => 'Nothing written this month';

  @override
  String get tapPencilToWrite => 'Tap the pencil to write an entry.';

  @override
  String get untitledEntry => 'Untitled entry';

  @override
  String get jumpToDate => 'Jump to a date';

  @override
  String get chooseCover => 'Choose a cover';

  @override
  String get coverAutomatic => 'Automatic';

  @override
  String get searchThisFolder => 'Search this fold';

  @override
  String get pasteTweetOrUrl => 'Paste a tweet or any URL.';

  @override
  String get urlHint => 'https://x.com/…';

  @override
  String get viewOpen => 'Open';

  @override
  String get viewBlocks => 'Blocks';

  @override
  String get noNotesYet => 'No nodes yet';

  @override
  String get tapPencilToAdd => 'Tap the pencil to add one.';

  @override
  String get noCardsYet => 'No sparks yet';

  @override
  String get shareOrPasteLink =>
      'Share a link to Braim, or tap + to paste one.';

  @override
  String get noMatches => 'No matches';

  @override
  String itemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String photosCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get emptyNote => 'Empty node';

  @override
  String get linkFallback => 'Link';

  @override
  String get sectionCortex => 'CORTEX';

  @override
  String get sectionNotes => 'NODES';

  @override
  String get sectionCards => 'SPARKS';

  @override
  String get sectionFolders => 'FOLDS';

  @override
  String get sectionArchived => 'ARCHIVED';

  @override
  String get sectionYourCortex => 'YOUR CORTEX';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => 'Unpin';

  @override
  String get move => 'Move to fold';

  @override
  String selectedCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get select => 'Select';

  @override
  String get moveToFolder => 'Move to fold';

  @override
  String get deleteTitle => 'Delete?';

  @override
  String deleteItemsConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'These $count items will move to Recently deleted, where they stay for 30 days.',
      one: 'This will move to Recently deleted, where it stays for 30 days.',
    );
    return '$_temp0';
  }

  @override
  String get archive => 'Archive';

  @override
  String get unarchive => 'Unarchive';

  @override
  String get moveToCortex => 'Move to cortex';

  @override
  String get newFolderSubtitle => 'Create a fold and move this into it';

  @override
  String get deleteKeptSubtitle => 'Kept in Recently deleted for 30 days';

  @override
  String pinLimitReached(int max) {
    return 'Pin limit reached (max $max)';
  }

  @override
  String get archived => 'Archived';

  @override
  String get unarchived => 'Unarchived';

  @override
  String get movedToTrash => 'Moved to Recently deleted';

  @override
  String movedToName(String name) {
    return 'Moved to \"$name\"';
  }

  @override
  String get noFolder => 'No fold';

  @override
  String get crypt => 'Crypt';

  @override
  String get cryptLockedSecret => 'Locked, secret';

  @override
  String get noFoldersYetCreate => 'No folds yet, create one in Cortex.';

  @override
  String get noFoldersYet => 'No folds yet';

  @override
  String get unlockCrypt => 'Unlock Crypt';

  @override
  String get unlockFailed => 'Unlock failed';

  @override
  String get newSpace => 'New fold';

  @override
  String get editSpace => 'Edit fold';

  @override
  String get spaceName => 'Fold name';

  @override
  String get folderColor => 'Fold colour';

  @override
  String get addThumbnail => 'Add thumbnail';

  @override
  String editNamed(String name) {
    return 'Edit \"$name\"';
  }

  @override
  String get archiveFolder => 'Archive fold';

  @override
  String get archiveFolderSubtitle => 'Hidden from Cortex; contents stay put';

  @override
  String get deleteFolder => 'Delete fold';

  @override
  String get folderArchived => 'Fold archived';

  @override
  String addToName(String name) {
    return 'Add to $name';
  }

  @override
  String get addRemoveHint => 'Tap an item to add or remove it from this fold.';

  @override
  String get noNotesOrCards => 'No nodes or sparks yet.';

  @override
  String get addExisting => 'Add existing';

  @override
  String get nothingInFolder => 'Nothing in this fold yet';

  @override
  String get useButtonsToAdd =>
      'Use the + buttons to add a node or existing items.';

  @override
  String get title => 'Title';

  @override
  String get writeSomething => 'Write something…';

  @override
  String get tapLineToFormat => 'Tap a line to format text';

  @override
  String get savedAutomatically => 'Saved automatically';

  @override
  String get addPhotos => 'Add photos';

  @override
  String get background => 'Background';

  @override
  String get noteBackground => 'Node background';

  @override
  String get copyNote => 'Copy node';

  @override
  String get noteCopied => 'Node copied to clipboard';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get bold => 'Bold';

  @override
  String get italic => 'Italic';

  @override
  String get underline => 'Underline';

  @override
  String get strikethrough => 'Strikethrough';

  @override
  String get highlight => 'Highlight';

  @override
  String get hyperlink => 'Link';

  @override
  String get selectTextToLink => 'Select some text first to add a link';

  @override
  String get addLink => 'Add link';

  @override
  String get editLink => 'Edit link';

  @override
  String get linkUrlHint => 'https://example.com';

  @override
  String get removeLink => 'Remove link';

  @override
  String get quote => 'Quote';

  @override
  String get indentDecrease => 'Decrease indent';

  @override
  String get indentIncrease => 'Increase indent';

  @override
  String get alignLeft => 'Align left';

  @override
  String get alignCenter => 'Align centre';

  @override
  String get alignRight => 'Align right';

  @override
  String get justify => 'Justify';

  @override
  String get bulletList => 'Bullet list';

  @override
  String get numberedList => 'Numbered list';

  @override
  String get heading => 'Heading';

  @override
  String get subHeading => 'Sub';

  @override
  String get body => 'Body';

  @override
  String get tapLineHint => 'Tap a line to format text';

  @override
  String get addATitle => 'Add a title';

  @override
  String get refreshPreview => 'Refresh preview';

  @override
  String get deleteCard => 'Delete spark';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get couldNotOpenLink => 'Could not open link';

  @override
  String get archiveTitle => 'Archive';

  @override
  String get nothingArchived => 'Nothing archived';

  @override
  String get archiveHint => 'Long-press a node, spark or fold to archive it.';

  @override
  String get longPressToRestore => 'Long-press anything to restore it.';

  @override
  String get noteUnarchived => 'Node unarchived';

  @override
  String get cardUnarchived => 'Spark unarchived';

  @override
  String get folderUnarchived => 'Fold unarchived';

  @override
  String get recentlyDeleted => 'Recently deleted';

  @override
  String get nothingHere => 'Nothing here';

  @override
  String get deletedKept30 => 'Deleted items are kept for 30 days.';

  @override
  String get trashHint =>
      'Items are deleted forever after 30 days. Tap one to restore it.';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get emptyTrashTitle => 'Empty Recently deleted?';

  @override
  String get emptyTrashBody =>
      'All nodes, sparks and folds here are permanently deleted.';

  @override
  String get settings => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get feedBackgroundSection => 'Feed background';

  @override
  String get feedBackgroundLabel => 'Home feed background';

  @override
  String get feedBackgroundChoose => 'Choose image';

  @override
  String get feedBackgroundLightMode => 'Light mode image';

  @override
  String get feedBackgroundDarkMode => 'Dark mode image';

  @override
  String get feedBackgroundReset => 'Reset to default';

  @override
  String get fontsSection => 'Fonts';

  @override
  String get bodyFontLabel => 'Node & spark body';

  @override
  String get bodyFontPreview => 'The quick brown fox jumps over the lazy dog.';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get followSystem => 'Follow system';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get sortBy => 'Sort by';

  @override
  String get sortRecent => 'Recently added';

  @override
  String get sortOldest => 'Oldest first';

  @override
  String get sortAz => 'Alphabetical (A–Z)';

  @override
  String get sortZa => 'Alphabetical (Z–A)';

  @override
  String get filterByTag => 'Filter by tag';

  @override
  String get tagAll => 'All tags';

  @override
  String get checklist => 'Checklist';

  @override
  String get noteColor => 'Colour';

  @override
  String get backupReminderTitle => 'Keep your nodes safe';

  @override
  String get backupReminderBody =>
      'Back up now so a lost phone doesn\'t mean lost nodes.';

  @override
  String get backupNow => 'Back up';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get lastBackupNever => 'Not backed up yet';

  @override
  String lastBackupAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Backed up $count days ago',
      one: 'Backed up yesterday',
      zero: 'Backed up today',
    );
    return '$_temp0';
  }

  @override
  String get backupSection => 'Backup';

  @override
  String get backupTitle => 'Back up (data + images)';

  @override
  String get infoCreated => 'Created';

  @override
  String get infoModified => 'Last modified';

  @override
  String get infoCharacters => 'Characters';

  @override
  String get restoreFromBackup => 'Restore from backup';

  @override
  String get restoreSubtitle => 'Pick a .zip backup file';

  @override
  String get restoreFromDeviceTitle => 'Restore from a device backup';

  @override
  String get restoreFromDeviceSubtitle =>
      'Pick one of the automatic copies kept on this device';

  @override
  String get deviceBackupsFolderLabel => 'Folder';

  @override
  String get devicePickTitle => 'Choose a device backup';

  @override
  String get deviceNoBackups => 'No device backups yet';

  @override
  String get load => 'Load';

  @override
  String get linksSection => 'Links';

  @override
  String mentionedIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places',
      one: '1 place',
    );
    return 'Mentioned in $_temp0';
  }

  @override
  String get untitledNote => 'Untitled node';

  @override
  String get linkToNote => 'Link to a node';

  @override
  String get mentionNodeHeader => 'Link a node';

  @override
  String get mentionThreadHeader => 'Mention a thread or impulse';

  @override
  String get searchOrCreateNote => 'Search or type a new title';

  @override
  String createNoteNamed(String name) {
    return 'Create \"$name\"';
  }

  @override
  String get noNotesToLink => 'No nodes to link yet';

  @override
  String get tapNoteThenLink => 'Tap in the node first, then add a link';

  @override
  String get journalSection => 'Journal';

  @override
  String get journalReminderTitle => 'Daily journal nudge';

  @override
  String get journalReminderSubtitle =>
      'A gentle reminder to write each evening';

  @override
  String get journalReminderTime => 'Reminder time';

  @override
  String journalYearEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries this year',
      one: '1 entry this year',
      zero: 'No entries yet',
    );
    return '$_temp0';
  }

  @override
  String get heatmapLess => 'Less';

  @override
  String get heatmapMore => 'More';

  @override
  String get versionHistory => 'Version history';

  @override
  String versionsSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved',
      one: '1 saved',
    );
    return '$_temp0';
  }

  @override
  String get saveVersion => 'Save version';

  @override
  String get versionSavedToast => 'Version saved';

  @override
  String get versionHistoryEmpty => 'No versions yet';

  @override
  String get versionHistoryEmptyBody =>
      'Save a version to snapshot this chapter, a heavy revise stays reversible.';

  @override
  String get versionCurrent => 'Current';

  @override
  String get versionAuto => 'Auto';

  @override
  String get versionSaved => 'Saved';

  @override
  String get versionNow => 'Now';

  @override
  String get versionJustNow => 'Just now';

  @override
  String versionToday(String time) {
    return 'Today, $time';
  }

  @override
  String versionYesterday(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get restoreVersion => 'Restore this version';

  @override
  String get restoreVersionBody =>
      'Your current text is saved as a version first, so you can undo this.';

  @override
  String get versionRestoredToast => 'Version restored';

  @override
  String get tabReflexes => 'Reflexes';

  @override
  String get newImpulse => 'New impulse';

  @override
  String get editImpulse => 'Edit impulse';

  @override
  String get edit => 'Edit';

  @override
  String get reflexesEmpty => 'No impulses yet';

  @override
  String get reflexesEmptyBody =>
      'An impulse is a project made of small threads you tick off. Start one to build momentum.';

  @override
  String get untitledImpulse => 'Untitled impulse';

  @override
  String get todayLabel => 'Today';

  @override
  String get overallLabel => 'Overall';

  @override
  String get impulseTitle => 'Title';

  @override
  String get impulseTitleHint => 'What\'s the project?';

  @override
  String get impulseGoal => 'What will you achieve?';

  @override
  String get impulseGoalHint => 'The goal you\'re chasing';

  @override
  String get impulseCategory => 'Category';

  @override
  String get impulseCategoryHint => 'e.g. Work, Personal';

  @override
  String get categoryWork => 'Work';

  @override
  String get categoryPersonal => 'Personal';

  @override
  String get impulseMode => 'Type';

  @override
  String get modeDaily => 'Daily';

  @override
  String get modeDailyDesc => 'Threads reset each day, track today\'s progress';

  @override
  String get modeChecklist => 'Checklist';

  @override
  String get modeChecklistDesc => 'Tick threads off once, fill toward 100%';

  @override
  String get modeLongTerm => 'Long-term';

  @override
  String get modeLongTermDesc =>
      'A goal split into sections and modules, plus a daily reminder list';

  @override
  String get impulseStartDate => 'Start date';

  @override
  String get noStartDate => 'No start date';

  @override
  String get impulseDeadline => 'Deadline';

  @override
  String get noDeadline => 'No deadline';

  @override
  String get datesSection => 'Dates';

  @override
  String get startShort => 'Start';

  @override
  String get dueShort => 'Due';

  @override
  String get setDates => 'Set dates';

  @override
  String get clearDatesAction => 'Clear dates';

  @override
  String heatmapDaysDone(int done, int total) {
    return '$done of $total days done';
  }

  @override
  String heatmapDaysLeft(int days) {
    return '$days days left';
  }

  @override
  String get consistency => 'Consistency';

  @override
  String get consistencyHint => 'Which days do you work on this?';

  @override
  String get threadsSection => 'Threads';

  @override
  String get noThreads => 'No threads yet, add the first one below.';

  @override
  String get rename => 'Rename';

  @override
  String get addSection => 'Add section';

  @override
  String get sectionHint => 'e.g. Year 1';

  @override
  String get addSubsection => 'Add module';

  @override
  String get subjectHint => 'e.g. Calculus';

  @override
  String get sectionsHeader => 'Sections';

  @override
  String get dailyReminder => 'Random Threads';

  @override
  String get untitledSection => 'Untitled';

  @override
  String get addThreadHint => 'New thread…';

  @override
  String get deleteImpulse => 'Delete impulse';

  @override
  String get deleteImpulseConfirm => 'Delete this impulse and all its threads?';

  @override
  String get overdue => 'Overdue';

  @override
  String daysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left',
      one: '1 day left',
      zero: 'Due today',
    );
    return '$_temp0';
  }

  @override
  String get onThisDay => 'On this day';

  @override
  String onThisDayYearsAgo(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years years ago',
      one: '1 year ago',
    );
    return '$_temp0';
  }

  @override
  String get saveToDevice => 'Save to device';

  @override
  String get sendBackupTitle => 'Send a copy';

  @override
  String get sendBackupSubtitle => 'Share to Drive, email, or another app';

  @override
  String get backupSavedToDevice => 'Backup saved';

  @override
  String get autoBackupTitle => 'Automatic backup';

  @override
  String get autoBackupSubtitle =>
      'Keep a .zip copy on this device on a schedule';

  @override
  String get autoBackupFrequency => 'How often';

  @override
  String get autoBackupDaily => 'Daily';

  @override
  String get autoBackupWeekly => 'Weekly';

  @override
  String get autoBackupMonthly => 'Monthly';

  @override
  String get autoBackupNote =>
      'These copies stay in the app\'s own storage, so they survive a bad save but not an uninstall or a lost phone. Use Back up from time to time to keep a copy somewhere safer. The five most recent are kept and older ones are removed for you.';

  @override
  String get loadSampleData => 'Load sample data';

  @override
  String get loadSampleDataSubtitle =>
      'Add demo nodes, sparks and a short book';

  @override
  String get sampleDataTitle => 'Load sample data?';

  @override
  String get sampleDataBody =>
      'This adds a set of demo nodes, saved sparks and a short book so you can try everything out. It won\'t touch what you already have.';

  @override
  String get sampleDataLoaded => 'Sample data added';

  @override
  String get preparingBackup => 'Preparing backup…';

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get backupRestored => 'Backup restored';

  @override
  String get restoreBackupTitle => 'Restore backup?';

  @override
  String get restoreBackupBody =>
      'This replaces your current nodes, sparks and folds with the ones in the backup.';

  @override
  String get storageSection => 'Storage';

  @override
  String get statNotes => 'Nodes';

  @override
  String get statCortex => 'Cortex';

  @override
  String get statCards => 'Sparks';

  @override
  String get clearAllData => 'Clear all data';

  @override
  String get clearAllDataTitle => 'Clear all data?';

  @override
  String get clearAllDataBody =>
      'This permanently deletes every node, fold and spark on this device.';

  @override
  String get aboutSection => 'About';

  @override
  String get aboutLine => 'A notes app · v1.0';

  @override
  String get savedToCards => 'Saved to Sparks';

  @override
  String get savedToNotes => 'Saved to Nodes';

  @override
  String get saveToBraim => 'Save to Braim';

  @override
  String get saveNoteToBraim => 'Save node to Braim';

  @override
  String get noLinkFound => 'No link found in the shared text';

  @override
  String savedToName(String name) {
    return 'Saved to $name';
  }

  @override
  String get createAndSave => 'Create & save';

  @override
  String get folderName => 'Fold name';

  @override
  String get readerSection => 'Reader';

  @override
  String get themeLabel => 'Theme';

  @override
  String get wallpaper => 'Background';

  @override
  String get moreOptions => 'More';

  @override
  String get chooseTheme => 'Colour & background';

  @override
  String get createNote => 'Node';

  @override
  String get editAction => 'Edit';

  @override
  String get accountSection => 'Account';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signInSubtitle =>
      'Your nodes sync automatically and stay available everywhere.';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutSubtitle => 'Nodes stay on this device and stop syncing.';

  @override
  String get syncOn => 'Syncing automatically';

  @override
  String get signInFailed =>
      'Sign-in didn\'t work. Check your connection and try again.';

  @override
  String get syncNudgeTitle => 'Keep your nodes everywhere';

  @override
  String get syncNudgeBody =>
      'Sign in with Google and every node syncs by itself.';

  @override
  String get syncNudgeAction => 'Sign in';

  @override
  String get switchAccount => 'Switch account';

  @override
  String get theBooks => 'The Books';

  @override
  String get journalTab => 'Journal';

  @override
  String get booksEmptyTitle => 'Nothing on the shelf yet';

  @override
  String get booksEmptyBody => 'Tap the pencil to start your first book.';

  @override
  String get somethingWrong => 'Something went wrong. Try again.';

  @override
  String get newBook => 'New book';

  @override
  String get bookTitle => 'Book title';

  @override
  String get untitledBook => 'Untitled book';

  @override
  String get contentsPage => 'Contents';

  @override
  String get addChapter => 'Add chapter';

  @override
  String get addPage => 'Add page';

  @override
  String get shareAsPdf => 'Share as PDF';

  @override
  String get deleteBook => 'Delete book';

  @override
  String get deletePage => 'Delete page';

  @override
  String get changeCover => 'Change cover';

  @override
  String get renameBook => 'Rename book';

  @override
  String get chooseFont => 'Font';

  @override
  String pageLabel(int n) {
    return 'Page $n';
  }

  @override
  String get confirmDeleteBook =>
      'Delete this book and all its pages? This can\'t be undone.';

  @override
  String get bookDescription => 'Book description';

  @override
  String get addDescription => 'Add a short description';

  @override
  String get editDescription => 'Edit description';

  @override
  String byAuthor(String name) {
    return 'by $name';
  }

  @override
  String get readBook => 'Read';

  @override
  String get contentsSection => 'Contents';

  @override
  String wordsCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n words',
      one: '1 word',
    );
    return '$_temp0';
  }

  @override
  String chaptersCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n chapters',
      one: '1 chapter',
    );
    return '$_temp0';
  }

  @override
  String get statusDraft => 'Draft';

  @override
  String get statusRevised => 'Revised';

  @override
  String get statusFinal => 'Final';

  @override
  String get statusNone => 'No tag';

  @override
  String get chapterStatus => 'Status';

  @override
  String get export => 'Export';

  @override
  String get exportPdf => 'PDF';

  @override
  String get exportMarkdown => 'Markdown';

  @override
  String get exportEpub => 'ePub';

  @override
  String pageNOfM(int n, int m) {
    return 'Page $n of $m';
  }

  @override
  String get dragToReorder => 'Hold and drag to reorder';

  @override
  String get reorder => 'Reorder';

  @override
  String get done => 'Done';

  @override
  String get statMostActive => 'Most active time';

  @override
  String get statTotalEntries => 'Total entries';

  @override
  String get statLongestEntry => 'Longest word count';

  @override
  String get statTotalBooks => 'Total books';

  @override
  String get statPagesWritten => 'Pages written';

  @override
  String get statWordsWritten => 'Words written';

  @override
  String get readerSettings => 'Themes & Settings';

  @override
  String get highlightsAndNotes => 'Highlights & nodes';

  @override
  String get noHighlightsYet =>
      'Nothing highlighted yet. Select any text while reading.';

  @override
  String get annotateNote => 'Node';

  @override
  String get annotateHighlight => 'Highlight';

  @override
  String get translate => 'Translate';

  @override
  String get dictionary => 'Dictionary';

  @override
  String get share => 'Share';

  @override
  String get noteHint => 'What do you make of it?';

  @override
  String get bookAuthor => 'Author';

  @override
  String get setAuthor => 'Set author';

  @override
  String get authorHint => 'Who\'s writing this?';

  @override
  String get bookFont => 'Typeface';

  @override
  String get bookFontTitle => 'Book typeface';

  @override
  String get bookFontSample => 'The quick brown fox jumps over the lazy dog.';

  @override
  String get bookNotesSection => 'Nodes';

  @override
  String get bookNoteAdd => 'New node';

  @override
  String get bookNotesEmpty =>
      'Jot down characters, places and plot ideas here. They stay out of the manuscript.';

  @override
  String get bookNoteUntitled => 'Untitled node';

  @override
  String get bookNoteDelete => 'Delete node';

  @override
  String get linkToChapter => 'Link to chapter';

  @override
  String get unlink => 'Unlink';

  @override
  String get statWords => 'Words';

  @override
  String get statCharacters => 'Characters';

  @override
  String get statMinRead => 'Min read';

  @override
  String get wordTarget => 'Word target';

  @override
  String get wordTargetHint => 'e.g. 2000 (0 to clear)';

  @override
  String get addFrontBackMatter => 'Add front/back matter';

  @override
  String get matterDedication => 'Dedication';

  @override
  String get matterEpigraph => 'Epigraph';

  @override
  String get matterAcknowledgements => 'Acknowledgements';

  @override
  String get findAndReplace => 'Find & replace';

  @override
  String get findLabel => 'Find';

  @override
  String get replaceWithLabel => 'Replace with';

  @override
  String get caseSensitive => 'Case sensitive';

  @override
  String get replaceAll => 'Replace all';

  @override
  String matchesFound(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n matches',
      one: '1 match',
      zero: 'No matches',
    );
    return '$_temp0';
  }

  @override
  String replaceAllConfirm(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Replace $n occurrences across the book?',
      one: 'Replace 1 occurrence across the book?',
    );
    return '$_temp0';
  }

  @override
  String replacedCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n replacements made',
      one: '1 replacement made',
      zero: 'Nothing replaced',
    );
    return '$_temp0';
  }

  @override
  String get searchChapters => 'Search chapters';

  @override
  String get noChaptersMatch => 'No chapters match';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get bookmarkThisSpot => 'Bookmark this spot';

  @override
  String get bookmarkAdded => 'Bookmarked';

  @override
  String get noBookmarks =>
      'No bookmarks yet. Tap the bookmark icon while reading.';

  @override
  String bookmarkAt(int pct) {
    return 'At $pct%';
  }

  @override
  String get holdForCalendar => 'Hold the week for the calendar';

  @override
  String get dailyDay => 'Your daily day';

  @override
  String get dailyDayAdd => 'Add to your day…';

  @override
  String get dailyDayEmpty => 'Nothing planned yet';

  @override
  String get dailyDaySubtitle => 'Tap to plan and tick off your day';

  @override
  String get reflexes => 'Reflexes';

  @override
  String get pauseImpulse => 'Pause impulse';

  @override
  String get resumeImpulse => 'Resume impulse';

  @override
  String get markComplete => 'Mark as complete';

  @override
  String get markActive => 'Mark as active';

  @override
  String get pinToFeed => 'Pin to journal';

  @override
  String get unpinFromFeed => 'Unpin from journal';

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get archiveImpulse => 'Archive impulse';

  @override
  String get unarchiveImpulse => 'Unarchive';

  @override
  String get sortByPriority => 'Sort by priority';

  @override
  String get filterActive => 'Active';

  @override
  String get filterDone => 'Done';

  @override
  String get filterArchived => 'Archived';

  @override
  String get filterAll => 'All';

  @override
  String get pomodoro => 'Pomodoro';

  @override
  String get focusTimer => 'Focus timer';

  @override
  String get focusTitle => 'Focus';

  @override
  String get pomodoroStart => 'Start';

  @override
  String get pomodoroPause => 'Pause';

  @override
  String get pomodoroResume => 'Resume';

  @override
  String get pomodoroFocus => 'Focus';

  @override
  String get pomodoroBreak => 'Break';

  @override
  String get pomodoroComplete => 'All done';

  @override
  String get pomodoroFocusMin => 'Focus';

  @override
  String get pomodoroBreakMin => 'Break';

  @override
  String get pomodoroRounds => 'Rounds';

  @override
  String get pomodoroRound => 'Round';

  @override
  String get pomodoroPaused => 'Paused';

  @override
  String get pomodoroBreakSoon => 'Break time';

  @override
  String get pomodoroBackToFocus => 'Back to focus';

  @override
  String get pomodoroSessionDone => 'Focus session complete';

  @override
  String get pomodoroSettings => 'Focus setup';

  @override
  String get pomodoroEnd => 'End session';

  @override
  String get focusRunningHint =>
      'Timer keeps running in the background, you can leave';

  @override
  String get dndTitle => 'Do Not Disturb';

  @override
  String get dndOff => 'Off';

  @override
  String get dndOffDesc => 'Notifications stay on';

  @override
  String get dndFocus => 'Focus';

  @override
  String get dndFocusDesc => 'Silence notifications; calls still show, no ring';

  @override
  String get dndSilence => 'Total silence';

  @override
  String get dndSilenceDesc => 'Silence everything, calls included';

  @override
  String get dndGrantTitle => 'Allow Do Not Disturb?';

  @override
  String get dndGrantBody =>
      'Braim needs one-time Do Not Disturb access to mute your phone during focus. Nothing is read.';

  @override
  String get dndGrant => 'Open settings';

  @override
  String get dndCallsNote =>
      'Calls always appear silently from the top, pick Total silence to hide them too.';

  @override
  String get moveTask => 'Move';

  @override
  String get moveTaskTitle => 'Move to reflex';

  @override
  String get dayComplete => 'All done for today!';

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-day streak',
      one: '1-day streak',
    );
    return '$_temp0';
  }

  @override
  String streakBest(int count) {
    return 'best $count';
  }

  @override
  String get restDay => 'Rest day';

  @override
  String get todaysProgress => 'Today\'s progress';

  @override
  String get progressTotal => 'Total';

  @override
  String get progressCompleted => 'Completed';

  @override
  String get progressPending => 'Pending';

  @override
  String get progressAllClear => 'Nothing due today';

  @override
  String get perfectDay => 'Perfect day';

  @override
  String get nextUp => 'Next up';

  @override
  String get analyticsTitle => 'Analytics';

  @override
  String get analyticsCurrentStreak => 'Current streak';

  @override
  String get analyticsBestStreak => 'Best streak';

  @override
  String get analyticsThreads => 'Threads';

  @override
  String get analyticsActiveDays => 'Active days';

  @override
  String get analyticsWritingTime => 'Time writing';

  @override
  String get analyticsAllReflexes => 'All reflexes';

  @override
  String get analyticsScopeAll => 'All';

  @override
  String get analyticsConsistency => 'Consistency';

  @override
  String get analyticsPeriodToday => 'Today';

  @override
  String get analyticsPeriodWeek => '1W';

  @override
  String get analyticsPeriodMonth => '1M';

  @override
  String get analyticsPeriodYear => '1Y';

  @override
  String get analyticsPeriodAll => 'All';

  @override
  String get analyticsPeriodMax => 'Max';

  @override
  String get analyticsAllImpulses => 'All impulses';

  @override
  String get analyticsTrackLabel => 'Track';

  @override
  String get analyticsAverage => 'Average progress';

  @override
  String get analyticsMissed => 'Missed';

  @override
  String get proceed => 'Proceed';

  @override
  String get editPastTitle => 'Editing a past day';

  @override
  String get editPastBody =>
      'You\'re changing a task in the past. Are you sure you want to proceed?';

  @override
  String get editFutureTitle => 'Editing a future day';

  @override
  String get editFutureBody =>
      'You\'re changing a task in the future. Are you sure you want to proceed?';

  @override
  String get analyticsComingSoon =>
      'Deeper analytics, trends, per-thread breakdowns and more, are coming soon.';

  @override
  String get pickProgressImpulse => 'Track progress for';

  @override
  String get combinedProgressLabel => 'All reflexes today';

  @override
  String get cropTitle => 'Crop';

  @override
  String get cropReset => 'Reset';

  @override
  String get cropFreeform => 'Free';

  @override
  String get cropSquare => 'Square';

  @override
  String get consistencyHeatmap => 'Consistency';

  @override
  String get historyTitle => 'History';

  @override
  String get historyJumpToDate => 'Jump to date';

  @override
  String get textStyle => 'Text style';

  @override
  String get textSize => 'Text size';

  @override
  String get resetSize => 'Reset';

  @override
  String get moveCheckedToBottom => 'Move ticked items to the bottom';

  @override
  String get backgroundForDark => 'Background for dark mode';

  @override
  String get backgroundForLight => 'Background for light mode';

  @override
  String get historyEmpty => 'No task history yet.';

  @override
  String get historyNoTasksDay => 'No tasks scheduled this day.';

  @override
  String historyCompletedOf(int done, int total) {
    return '$done of $total completed';
  }

  @override
  String get rearrangeJournal => 'Rearrange';

  @override
  String get rearrangeJournalHint => 'Drag to reorder your journal sections.';

  @override
  String get sectionDailyTasks => 'Daily day';

  @override
  String get sectionReflexCard => 'Reflexes card';

  @override
  String get sectionDiaryEntries => 'Diary entries';

  @override
  String get composeDailyTask => 'Add to your daily day';

  @override
  String get composeReflex => 'New reflex';

  @override
  String get composeEntry => 'New journal entry';

  @override
  String reflexesProjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projects',
      one: '1 project',
      zero: 'No projects',
    );
    return '$_temp0';
  }

  @override
  String get newThread => 'New thread';

  @override
  String get taskComplete => 'Complete';

  @override
  String get taskUndo => 'Undo';

  @override
  String get taskRemove => 'Remove';

  @override
  String get important => 'Important';

  @override
  String get flagBest => 'Best to have';

  @override
  String get flagOptional => 'Optional';

  @override
  String get priority => 'Priority';

  @override
  String get descriptionAction => 'Description';

  @override
  String get startTime => 'Start';

  @override
  String get endTime => 'End';

  @override
  String get setTime => 'Set time';

  @override
  String get setStartFirst => 'Set start first';

  @override
  String get clearTime => 'Clear time';

  @override
  String get changeAllTimes => 'Change all times';

  @override
  String get changeAllTimesHint =>
      'Apply one time window to every task in this impulse.';

  @override
  String get noEndTime => 'None';

  @override
  String get apply => 'Apply';

  @override
  String allTimesUpdated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks moved to the new time',
      one: '1 task moved to the new time',
      zero: 'No tasks to update',
    );
    return '$_temp0';
  }

  @override
  String get notifyAtStart => 'Notify me at the start time';

  @override
  String get daysSection => 'Days';

  @override
  String get daysHint => 'Pick the days this runs on (none = every day).';

  @override
  String get repeatOnce => 'Once';

  @override
  String get repeatEveryday => 'Everyday';

  @override
  String get repeatOnceHint =>
      'A one-time task. Tick it off and it stays, done, until you delete it.';

  @override
  String get linkLabelHint => 'Label (e.g. Google Meet)';

  @override
  String get locationSection => 'Location';

  @override
  String get addLocation => 'Add address';

  @override
  String get openInMaps => 'Open in Maps';

  @override
  String get descriptionHint => 'Add a description…';

  @override
  String get editTask => 'Edit task';

  @override
  String inTime(String rel) {
    return 'In $rel';
  }

  @override
  String get timePassed => 'Passed';

  @override
  String get removeTaskConfirm => 'Remove this task?';

  @override
  String get wallpaperGreen => 'Green blooms';

  @override
  String get wallpaperRed => 'Red blooms';

  @override
  String get wallpaperBlue => 'Blue blooms';

  @override
  String get wallpaperBlack => 'Black blooms';

  @override
  String get tutWelcomeTitle => 'Welcome to Braim';

  @override
  String get tutWelcomeBody =>
      'A node is a note. Your nodes live on Home. Tap the pencil to write one and it saves as you type. The editor gives you bold, italic, highlight, headings, lists and checklists, and you can add photos, crop them and set the text size. You can also bring in files. Share a .md or .txt file to Braim, or open one, and it becomes a node. A Markdown node opens in a clean reader that renders headings, tables, links and code the way GitHub does. Press and hold any node for quick actions.';

  @override
  String get tutCardsTitle => 'Sparks';

  @override
  String get tutCardsBody =>
      'A spark is a saved link. Share a link from any app to Braim and it lands here with no app switching. Braim reads the title, thumbnail and description once and stores them in the spark, so it does not fetch them again. Write your own note under any spark. Duplicates merge on their own. Use the toggle to switch the feed between Open and Blocks views.';

  @override
  String get tutCortexTitle => 'Cortex';

  @override
  String get tutCortexBody =>
      'Cortex holds your folders, called folds. A fold groups related nodes and sparks together. Make one with the plus button and give it a cover photo if you like. To file an item, press and hold it and pick the fold. Open a fold to see only what it holds. You can also hide a fold from Home to keep it apart.';

  @override
  String get tutReflexesTitle => 'Reflexes';

  @override
  String get tutReflexesBody =>
      'Reflexes hold your habits, goals and projects. Each one is an impulse. An impulse contains threads, which are the tasks you tick off. A daily impulse resets its threads every morning and the bar shows today\'s progress. A milestone impulse keeps each thread ticked for good and the bar fills toward the finish. Give a thread a time and it sends you a reminder. Tap the heatmap to open the full day by day history.';

  @override
  String get tutBooksTitle => 'Books';

  @override
  String get tutBooksBody =>
      'Write long pieces as books made of chapters. Read them in a clean scrolling reader with themes, adjustable font size, bookmarks and highlights.';

  @override
  String get tutJournalTitle => 'Journal';

  @override
  String get tutJournalBody =>
      'Keep a daily diary from the Journal tab. Each entry stays tied to its day. Journal entries never show up on Home or in search.';

  @override
  String get tutCryptTitle => 'Crypt';

  @override
  String get tutCryptBody =>
      'Crypt is a fold that opens only with your fingerprint or screen lock. Its contents stay out of every feed and out of search. It hides items rather than encrypting them, so keep passwords and bank details in a proper password manager.';

  @override
  String get tutTipsTitle => 'Good to know';

  @override
  String get tutTipsBody =>
      'Search covers nodes, sparks and folds in one place, and it reads your tags too. Pin up to 10 favourites in each feed. Sort a feed or filter it by tag from the sort button, and press and hold the search button inside a fold to sort it the same way. Archive hides items without deleting them. Deleted items wait 30 days in Recently deleted. Set backups, dark mode and reminders in Settings.';

  @override
  String get guideTitle => 'How Braim works';

  @override
  String get guideSettingsLabel => 'Guide';
}

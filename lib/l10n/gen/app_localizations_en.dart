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
  String get tabCards => 'Cards';

  @override
  String get tabJournal => 'Journal';

  @override
  String get tabCortex => 'Cortex';

  @override
  String get subtitleHome => 'Your notes';

  @override
  String get subtitleCards => 'Tweets & links you saved';

  @override
  String get subtitleJournal => 'One day at a time';

  @override
  String get subtitleCortex => 'Folders for notes & cards';

  @override
  String get searchHint => 'Search notes, cards, cortex';

  @override
  String get menu => 'Menu';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get restore => 'Restore';

  @override
  String get open => 'Open';

  @override
  String get copy => 'Copy';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get getStarted => 'Get started';

  @override
  String get empty => 'Empty';

  @override
  String get newNote => 'New note';

  @override
  String get saveALink => 'Save a link';

  @override
  String get newFolder => 'New folder';

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
  String get searchThisFolder => 'Search this folder';

  @override
  String get pasteTweetOrUrl => 'Paste a tweet or any URL.';

  @override
  String get urlHint => 'https://x.com/…';

  @override
  String get viewOpen => 'Open';

  @override
  String get viewBlocks => 'Blocks';

  @override
  String get noNotesYet => 'No notes yet';

  @override
  String get tapPencilToAdd => 'Tap the pencil to add one.';

  @override
  String get noCardsYet => 'No cards yet';

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
  String get emptyNote => 'Empty note';

  @override
  String get linkFallback => 'Link';

  @override
  String get sectionCortex => 'CORTEX';

  @override
  String get sectionNotes => 'NOTES';

  @override
  String get sectionCards => 'CARDS';

  @override
  String get sectionFolders => 'FOLDERS';

  @override
  String get sectionArchived => 'ARCHIVED';

  @override
  String get sectionYourCortex => 'YOUR CORTEX';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => 'Unpin';

  @override
  String get archive => 'Archive';

  @override
  String get unarchive => 'Unarchive';

  @override
  String get moveToCortex => 'Move to cortex';

  @override
  String get newFolderSubtitle => 'Create a folder and move this into it';

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
  String get noFolder => 'No folder';

  @override
  String get crypt => 'Crypt';

  @override
  String get cryptLockedSecret => 'Locked, secret';

  @override
  String get noFoldersYetCreate => 'No folders yet — create one in Cortex.';

  @override
  String get noFoldersYet => 'No folders yet';

  @override
  String get unlockCrypt => 'Unlock Crypt';

  @override
  String get unlockFailed => 'Unlock failed';

  @override
  String get newSpace => 'New space';

  @override
  String get editSpace => 'Edit space';

  @override
  String get spaceName => 'Space name';

  @override
  String get addThumbnail => 'Add thumbnail';

  @override
  String editNamed(String name) {
    return 'Edit \"$name\"';
  }

  @override
  String get archiveFolder => 'Archive folder';

  @override
  String get archiveFolderSubtitle => 'Hidden from Cortex; contents stay put';

  @override
  String get deleteFolder => 'Delete folder';

  @override
  String get folderArchived => 'Folder archived';

  @override
  String addToName(String name) {
    return 'Add to $name';
  }

  @override
  String get addRemoveHint =>
      'Tap an item to add or remove it from this folder.';

  @override
  String get noNotesOrCards => 'No notes or cards yet.';

  @override
  String get addExisting => 'Add existing';

  @override
  String get nothingInFolder => 'Nothing in this folder yet';

  @override
  String get useButtonsToAdd =>
      'Use the + buttons to add a note or existing items.';

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
  String get noteBackground => 'Note background';

  @override
  String get copyNote => 'Copy note';

  @override
  String get noteCopied => 'Note copied to clipboard';

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
  String get highlight => 'Highlight';

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
  String get deleteCard => 'Delete card';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get couldNotOpenLink => 'Could not open link';

  @override
  String get archiveTitle => 'Archive';

  @override
  String get nothingArchived => 'Nothing archived';

  @override
  String get archiveHint => 'Long-press a note, card or folder to archive it.';

  @override
  String get longPressToRestore => 'Long-press anything to restore it.';

  @override
  String get noteUnarchived => 'Note unarchived';

  @override
  String get cardUnarchived => 'Card unarchived';

  @override
  String get folderUnarchived => 'Folder unarchived';

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
      'All notes, cards and folders here are permanently deleted.';

  @override
  String get settings => 'Settings';

  @override
  String get appearance => 'Appearance';

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
  String get checklist => 'Checklist';

  @override
  String get noteColor => 'Colour';

  @override
  String get backupReminderTitle => 'Keep your notes safe';

  @override
  String get backupReminderBody =>
      'Back up now so a lost phone doesn\'t mean lost notes.';

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
  String get backupSubtitle => 'Share to Google Drive, Files, …';

  @override
  String get restoreFromBackup => 'Restore from backup';

  @override
  String get restoreSubtitle => 'Pick a .zip backup file';

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
      'This replaces your current notes, cards and folders with the ones in the backup.';

  @override
  String get storageSection => 'Storage';

  @override
  String get statNotes => 'Notes';

  @override
  String get statCortex => 'Cortex';

  @override
  String get statCards => 'Cards';

  @override
  String get clearAllData => 'Clear all data';

  @override
  String get clearAllDataTitle => 'Clear all data?';

  @override
  String get clearAllDataBody =>
      'This permanently deletes every note, space and card on this device.';

  @override
  String get aboutSection => 'About';

  @override
  String get aboutLine => 'A glassy notes app · v1.0';

  @override
  String get savedToCards => 'Saved to Cards';

  @override
  String get saveToBraim => 'Save to Braim';

  @override
  String get noLinkFound => 'No link found in the shared text';

  @override
  String savedToName(String name) {
    return 'Saved to $name';
  }

  @override
  String get createAndSave => 'Create & save';

  @override
  String get folderName => 'Folder name';

  @override
  String get readerSection => 'Reader';

  @override
  String get themeLabel => 'Theme';

  @override
  String get wallpaper => 'Background';

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
      'Your notes live on Home. Tap the pencil to write one — it saves automatically. Long-press any note for quick actions.';

  @override
  String get tutCardsTitle => 'Cards';

  @override
  String get tutCardsBody =>
      'Share a link from any app to Braim and a small popup saves it as a card — no app switching. Duplicates merge automatically. Switch the feed between Open and Blocks views with the toggle.';

  @override
  String get tutCortexTitle => 'Cortex';

  @override
  String get tutCortexBody =>
      'Folders for your notes and cards. Create one with the + button, give it a photo thumbnail, or file things from the long-press menu.';

  @override
  String get tutCryptTitle => 'Crypt';

  @override
  String get tutCryptBody =>
      'A folder that only opens with your fingerprint or screen lock — its contents never appear in feeds or search.\n\nHeads up: Crypt locks the door, but items are stored unencrypted on this device and included readable in backups. Don\'t keep passwords or bank details in it.';

  @override
  String get tutTipsTitle => 'Good to know';

  @override
  String get tutTipsBody =>
      'Search finds notes, cards and folders in one place. Pin up to 10 favourites per feed. Archive hides without deleting; deleted items wait 30 days in Recently deleted. Back up everything from Settings — and there\'s a dark mode in there too.';
}

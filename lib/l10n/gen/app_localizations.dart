import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Braim'**
  String get appTitle;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get tabCards;

  /// No description provided for @tabJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get tabJournal;

  /// No description provided for @tabCortex.
  ///
  /// In en, this message translates to:
  /// **'Cortex'**
  String get tabCortex;

  /// No description provided for @subtitleHome.
  ///
  /// In en, this message translates to:
  /// **'Your notes'**
  String get subtitleHome;

  /// No description provided for @subtitleCards.
  ///
  /// In en, this message translates to:
  /// **'Tweets & links you saved'**
  String get subtitleCards;

  /// No description provided for @subtitleJournal.
  ///
  /// In en, this message translates to:
  /// **'One day at a time'**
  String get subtitleJournal;

  /// No description provided for @subtitleCortex.
  ///
  /// In en, this message translates to:
  /// **'Folders for notes & cards'**
  String get subtitleCortex;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search notes, cards, cortex'**
  String get searchHint;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get empty;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get newNote;

  /// No description provided for @saveALink.
  ///
  /// In en, this message translates to:
  /// **'Save a link'**
  String get saveALink;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// No description provided for @newEntry.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get newEntry;

  /// No description provided for @sectionEntries.
  ///
  /// In en, this message translates to:
  /// **'ENTRIES'**
  String get sectionEntries;

  /// No description provided for @sectionYears.
  ///
  /// In en, this message translates to:
  /// **'YEARS'**
  String get sectionYears;

  /// No description provided for @noEntriesForDay.
  ///
  /// In en, this message translates to:
  /// **'Nothing written this day'**
  String get noEntriesForDay;

  /// No description provided for @noEntriesThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Nothing written this month'**
  String get noEntriesThisMonth;

  /// No description provided for @tapPencilToWrite.
  ///
  /// In en, this message translates to:
  /// **'Tap the pencil to write an entry.'**
  String get tapPencilToWrite;

  /// No description provided for @untitledEntry.
  ///
  /// In en, this message translates to:
  /// **'Untitled entry'**
  String get untitledEntry;

  /// No description provided for @jumpToDate.
  ///
  /// In en, this message translates to:
  /// **'Jump to a date'**
  String get jumpToDate;

  /// No description provided for @chooseCover.
  ///
  /// In en, this message translates to:
  /// **'Choose a cover'**
  String get chooseCover;

  /// No description provided for @coverAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get coverAutomatic;

  /// No description provided for @searchThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Search this folder'**
  String get searchThisFolder;

  /// No description provided for @pasteTweetOrUrl.
  ///
  /// In en, this message translates to:
  /// **'Paste a tweet or any URL.'**
  String get pasteTweetOrUrl;

  /// No description provided for @urlHint.
  ///
  /// In en, this message translates to:
  /// **'https://x.com/…'**
  String get urlHint;

  /// No description provided for @viewOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get viewOpen;

  /// No description provided for @viewBlocks.
  ///
  /// In en, this message translates to:
  /// **'Blocks'**
  String get viewBlocks;

  /// No description provided for @noNotesYet.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get noNotesYet;

  /// No description provided for @tapPencilToAdd.
  ///
  /// In en, this message translates to:
  /// **'Tap the pencil to add one.'**
  String get tapPencilToAdd;

  /// No description provided for @noCardsYet.
  ///
  /// In en, this message translates to:
  /// **'No cards yet'**
  String get noCardsYet;

  /// No description provided for @shareOrPasteLink.
  ///
  /// In en, this message translates to:
  /// **'Share a link to Braim, or tap + to paste one.'**
  String get shareOrPasteLink;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatches;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String itemsCount(int count);

  /// No description provided for @photosCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String photosCount(int count);

  /// No description provided for @emptyNote.
  ///
  /// In en, this message translates to:
  /// **'Empty note'**
  String get emptyNote;

  /// No description provided for @linkFallback.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get linkFallback;

  /// No description provided for @sectionCortex.
  ///
  /// In en, this message translates to:
  /// **'CORTEX'**
  String get sectionCortex;

  /// No description provided for @sectionNotes.
  ///
  /// In en, this message translates to:
  /// **'NOTES'**
  String get sectionNotes;

  /// No description provided for @sectionCards.
  ///
  /// In en, this message translates to:
  /// **'CARDS'**
  String get sectionCards;

  /// No description provided for @sectionFolders.
  ///
  /// In en, this message translates to:
  /// **'FOLDERS'**
  String get sectionFolders;

  /// No description provided for @sectionArchived.
  ///
  /// In en, this message translates to:
  /// **'ARCHIVED'**
  String get sectionArchived;

  /// No description provided for @sectionYourCortex.
  ///
  /// In en, this message translates to:
  /// **'YOUR CORTEX'**
  String get sectionYourCortex;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @unarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchive;

  /// No description provided for @moveToCortex.
  ///
  /// In en, this message translates to:
  /// **'Move to cortex'**
  String get moveToCortex;

  /// No description provided for @newFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a folder and move this into it'**
  String get newFolderSubtitle;

  /// No description provided for @deleteKeptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Kept in Recently deleted for 30 days'**
  String get deleteKeptSubtitle;

  /// No description provided for @pinLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Pin limit reached (max {max})'**
  String pinLimitReached(int max);

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @unarchived.
  ///
  /// In en, this message translates to:
  /// **'Unarchived'**
  String get unarchived;

  /// No description provided for @movedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved to Recently deleted'**
  String get movedToTrash;

  /// No description provided for @movedToName.
  ///
  /// In en, this message translates to:
  /// **'Moved to \"{name}\"'**
  String movedToName(String name);

  /// No description provided for @noFolder.
  ///
  /// In en, this message translates to:
  /// **'No folder'**
  String get noFolder;

  /// No description provided for @crypt.
  ///
  /// In en, this message translates to:
  /// **'Crypt'**
  String get crypt;

  /// No description provided for @cryptLockedSecret.
  ///
  /// In en, this message translates to:
  /// **'Locked, secret'**
  String get cryptLockedSecret;

  /// No description provided for @noFoldersYetCreate.
  ///
  /// In en, this message translates to:
  /// **'No folders yet — create one in Cortex.'**
  String get noFoldersYetCreate;

  /// No description provided for @noFoldersYet.
  ///
  /// In en, this message translates to:
  /// **'No folders yet'**
  String get noFoldersYet;

  /// No description provided for @unlockCrypt.
  ///
  /// In en, this message translates to:
  /// **'Unlock Crypt'**
  String get unlockCrypt;

  /// No description provided for @unlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Unlock failed'**
  String get unlockFailed;

  /// No description provided for @newSpace.
  ///
  /// In en, this message translates to:
  /// **'New space'**
  String get newSpace;

  /// No description provided for @editSpace.
  ///
  /// In en, this message translates to:
  /// **'Edit space'**
  String get editSpace;

  /// No description provided for @spaceName.
  ///
  /// In en, this message translates to:
  /// **'Space name'**
  String get spaceName;

  /// No description provided for @addThumbnail.
  ///
  /// In en, this message translates to:
  /// **'Add thumbnail'**
  String get addThumbnail;

  /// No description provided for @editNamed.
  ///
  /// In en, this message translates to:
  /// **'Edit \"{name}\"'**
  String editNamed(String name);

  /// No description provided for @archiveFolder.
  ///
  /// In en, this message translates to:
  /// **'Archive folder'**
  String get archiveFolder;

  /// No description provided for @archiveFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hidden from Cortex; contents stay put'**
  String get archiveFolderSubtitle;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolder;

  /// No description provided for @folderArchived.
  ///
  /// In en, this message translates to:
  /// **'Folder archived'**
  String get folderArchived;

  /// No description provided for @addToName.
  ///
  /// In en, this message translates to:
  /// **'Add to {name}'**
  String addToName(String name);

  /// No description provided for @addRemoveHint.
  ///
  /// In en, this message translates to:
  /// **'Tap an item to add or remove it from this folder.'**
  String get addRemoveHint;

  /// No description provided for @noNotesOrCards.
  ///
  /// In en, this message translates to:
  /// **'No notes or cards yet.'**
  String get noNotesOrCards;

  /// No description provided for @addExisting.
  ///
  /// In en, this message translates to:
  /// **'Add existing'**
  String get addExisting;

  /// No description provided for @nothingInFolder.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this folder yet'**
  String get nothingInFolder;

  /// No description provided for @useButtonsToAdd.
  ///
  /// In en, this message translates to:
  /// **'Use the + buttons to add a note or existing items.'**
  String get useButtonsToAdd;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @writeSomething.
  ///
  /// In en, this message translates to:
  /// **'Write something…'**
  String get writeSomething;

  /// No description provided for @tapLineToFormat.
  ///
  /// In en, this message translates to:
  /// **'Tap a line to format text'**
  String get tapLineToFormat;

  /// No description provided for @savedAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Saved automatically'**
  String get savedAutomatically;

  /// No description provided for @addPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add photos'**
  String get addPhotos;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @noteBackground.
  ///
  /// In en, this message translates to:
  /// **'Note background'**
  String get noteBackground;

  /// No description provided for @copyNote.
  ///
  /// In en, this message translates to:
  /// **'Copy note'**
  String get copyNote;

  /// No description provided for @noteCopied.
  ///
  /// In en, this message translates to:
  /// **'Note copied to clipboard'**
  String get noteCopied;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// No description provided for @italic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italic;

  /// No description provided for @underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underline;

  /// No description provided for @highlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlight;

  /// No description provided for @bulletList.
  ///
  /// In en, this message translates to:
  /// **'Bullet list'**
  String get bulletList;

  /// No description provided for @numberedList.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get numberedList;

  /// No description provided for @heading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get heading;

  /// No description provided for @subHeading.
  ///
  /// In en, this message translates to:
  /// **'Sub'**
  String get subHeading;

  /// No description provided for @body.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get body;

  /// No description provided for @tapLineHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a line to format text'**
  String get tapLineHint;

  /// No description provided for @addATitle.
  ///
  /// In en, this message translates to:
  /// **'Add a title'**
  String get addATitle;

  /// No description provided for @refreshPreview.
  ///
  /// In en, this message translates to:
  /// **'Refresh preview'**
  String get refreshPreview;

  /// No description provided for @deleteCard.
  ///
  /// In en, this message translates to:
  /// **'Delete card'**
  String get deleteCard;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get couldNotOpenLink;

  /// No description provided for @archiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveTitle;

  /// No description provided for @nothingArchived.
  ///
  /// In en, this message translates to:
  /// **'Nothing archived'**
  String get nothingArchived;

  /// No description provided for @archiveHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press a note, card or folder to archive it.'**
  String get archiveHint;

  /// No description provided for @longPressToRestore.
  ///
  /// In en, this message translates to:
  /// **'Long-press anything to restore it.'**
  String get longPressToRestore;

  /// No description provided for @noteUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Note unarchived'**
  String get noteUnarchived;

  /// No description provided for @cardUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Card unarchived'**
  String get cardUnarchived;

  /// No description provided for @folderUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Folder unarchived'**
  String get folderUnarchived;

  /// No description provided for @recentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recently deleted'**
  String get recentlyDeleted;

  /// No description provided for @nothingHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get nothingHere;

  /// No description provided for @deletedKept30.
  ///
  /// In en, this message translates to:
  /// **'Deleted items are kept for 30 days.'**
  String get deletedKept30;

  /// No description provided for @trashHint.
  ///
  /// In en, this message translates to:
  /// **'Items are deleted forever after 30 days. Tap one to restore it.'**
  String get trashHint;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// No description provided for @emptyTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty Recently deleted?'**
  String get emptyTrashTitle;

  /// No description provided for @emptyTrashBody.
  ///
  /// In en, this message translates to:
  /// **'All notes, cards and folders here are permanently deleted.'**
  String get emptyTrashBody;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystem;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDark;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @sortRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get sortRecent;

  /// No description provided for @sortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get sortOldest;

  /// No description provided for @sortAz.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical (A–Z)'**
  String get sortAz;

  /// No description provided for @sortZa.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical (Z–A)'**
  String get sortZa;

  /// No description provided for @checklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get checklist;

  /// No description provided for @noteColor.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get noteColor;

  /// No description provided for @backupReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep your notes safe'**
  String get backupReminderTitle;

  /// No description provided for @backupReminderBody.
  ///
  /// In en, this message translates to:
  /// **'Back up now so a lost phone doesn\'t mean lost notes.'**
  String get backupReminderBody;

  /// No description provided for @backupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up'**
  String get backupNow;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @lastBackupNever.
  ///
  /// In en, this message translates to:
  /// **'Not backed up yet'**
  String get lastBackupNever;

  /// No description provided for @lastBackupAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Backed up today} =1{Backed up yesterday} other{Backed up {count} days ago}}'**
  String lastBackupAgo(int count);

  /// No description provided for @backupSection.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupSection;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up (data + images)'**
  String get backupTitle;

  /// No description provided for @backupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share to Google Drive, Files, …'**
  String get backupSubtitle;

  /// No description provided for @restoreFromBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get restoreFromBackup;

  /// No description provided for @restoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a .zip backup file'**
  String get restoreSubtitle;

  /// No description provided for @preparingBackup.
  ///
  /// In en, this message translates to:
  /// **'Preparing backup…'**
  String get preparingBackup;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(String error);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get backupRestored;

  /// No description provided for @restoreBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore backup?'**
  String get restoreBackupTitle;

  /// No description provided for @restoreBackupBody.
  ///
  /// In en, this message translates to:
  /// **'This replaces your current notes, cards and folders with the ones in the backup.'**
  String get restoreBackupBody;

  /// No description provided for @storageSection.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageSection;

  /// No description provided for @statNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get statNotes;

  /// No description provided for @statCortex.
  ///
  /// In en, this message translates to:
  /// **'Cortex'**
  String get statCortex;

  /// No description provided for @statCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get statCards;

  /// No description provided for @clearAllData.
  ///
  /// In en, this message translates to:
  /// **'Clear all data'**
  String get clearAllData;

  /// No description provided for @clearAllDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear all data?'**
  String get clearAllDataTitle;

  /// No description provided for @clearAllDataBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes every note, space and card on this device.'**
  String get clearAllDataBody;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @aboutLine.
  ///
  /// In en, this message translates to:
  /// **'A glassy notes app · v1.0'**
  String get aboutLine;

  /// No description provided for @savedToCards.
  ///
  /// In en, this message translates to:
  /// **'Saved to Cards'**
  String get savedToCards;

  /// No description provided for @saveToBraim.
  ///
  /// In en, this message translates to:
  /// **'Save to Braim'**
  String get saveToBraim;

  /// No description provided for @noLinkFound.
  ///
  /// In en, this message translates to:
  /// **'No link found in the shared text'**
  String get noLinkFound;

  /// No description provided for @savedToName.
  ///
  /// In en, this message translates to:
  /// **'Saved to {name}'**
  String savedToName(String name);

  /// No description provided for @createAndSave.
  ///
  /// In en, this message translates to:
  /// **'Create & save'**
  String get createAndSave;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @readerSection.
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get readerSection;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get wallpaper;

  /// No description provided for @wallpaperGreen.
  ///
  /// In en, this message translates to:
  /// **'Green blooms'**
  String get wallpaperGreen;

  /// No description provided for @wallpaperRed.
  ///
  /// In en, this message translates to:
  /// **'Red blooms'**
  String get wallpaperRed;

  /// No description provided for @wallpaperBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue blooms'**
  String get wallpaperBlue;

  /// No description provided for @wallpaperBlack.
  ///
  /// In en, this message translates to:
  /// **'Black blooms'**
  String get wallpaperBlack;

  /// No description provided for @tutWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Braim'**
  String get tutWelcomeTitle;

  /// No description provided for @tutWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Your notes live on Home. Tap the pencil to write one — it saves automatically. Long-press any note for quick actions.'**
  String get tutWelcomeBody;

  /// No description provided for @tutCardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get tutCardsTitle;

  /// No description provided for @tutCardsBody.
  ///
  /// In en, this message translates to:
  /// **'Share a link from any app to Braim and a small popup saves it as a card — no app switching. Duplicates merge automatically. Switch the feed between Open and Blocks views with the toggle.'**
  String get tutCardsBody;

  /// No description provided for @tutCortexTitle.
  ///
  /// In en, this message translates to:
  /// **'Cortex'**
  String get tutCortexTitle;

  /// No description provided for @tutCortexBody.
  ///
  /// In en, this message translates to:
  /// **'Folders for your notes and cards. Create one with the + button, give it a photo thumbnail, or file things from the long-press menu.'**
  String get tutCortexBody;

  /// No description provided for @tutCryptTitle.
  ///
  /// In en, this message translates to:
  /// **'Crypt'**
  String get tutCryptTitle;

  /// No description provided for @tutCryptBody.
  ///
  /// In en, this message translates to:
  /// **'A folder that only opens with your fingerprint or screen lock — its contents never appear in feeds or search.\n\nHeads up: Crypt locks the door, but items are stored unencrypted on this device and included readable in backups. Don\'t keep passwords or bank details in it.'**
  String get tutCryptBody;

  /// No description provided for @tutTipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Good to know'**
  String get tutTipsTitle;

  /// No description provided for @tutTipsBody.
  ///
  /// In en, this message translates to:
  /// **'Search finds notes, cards and folders in one place. Pin up to 10 favourites per feed. Archive hides without deleting; deleted items wait 30 days in Recently deleted. Back up everything from Settings — and there\'s a dark mode in there too.'**
  String get tutTipsBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

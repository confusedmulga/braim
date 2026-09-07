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
  /// **'Sparks'**
  String get tabCards;

  /// No description provided for @tabJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get tabJournal;

  /// No description provided for @tabNarrative.
  ///
  /// In en, this message translates to:
  /// **'Narrative'**
  String get tabNarrative;

  /// No description provided for @tabCortex.
  ///
  /// In en, this message translates to:
  /// **'Cortex'**
  String get tabCortex;

  /// No description provided for @navEntries.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get navEntries;

  /// No description provided for @subtitleHome.
  ///
  /// In en, this message translates to:
  /// **'Your nodes'**
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
  /// **'Folds for nodes & sparks'**
  String get subtitleCortex;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search nodes, sparks, cortex'**
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

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get addTag;

  /// No description provided for @tagLabel.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tagLabel;

  /// No description provided for @tagHint.
  ///
  /// In en, this message translates to:
  /// **'idea, todo, work'**
  String get tagHint;

  /// No description provided for @reminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get reminder;

  /// No description provided for @reminderChange.
  ///
  /// In en, this message translates to:
  /// **'Change reminder'**
  String get reminderChange;

  /// No description provided for @reminderClear.
  ///
  /// In en, this message translates to:
  /// **'Clear reminder'**
  String get reminderClear;

  /// No description provided for @notifPermNeeded.
  ///
  /// In en, this message translates to:
  /// **'Turn on notifications to get reminders.'**
  String get notifPermNeeded;

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
  /// **'New node'**
  String get newNote;

  /// No description provided for @newMarkdown.
  ///
  /// In en, this message translates to:
  /// **'New markdown'**
  String get newMarkdown;

  /// No description provided for @importFile.
  ///
  /// In en, this message translates to:
  /// **'Import file'**
  String get importFile;

  /// No description provided for @markdownHint.
  ///
  /// In en, this message translates to:
  /// **'Write or paste Markdown…'**
  String get markdownHint;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @saveALink.
  ///
  /// In en, this message translates to:
  /// **'Save a link'**
  String get saveALink;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New fold'**
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
  /// **'Search this fold'**
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
  /// **'No nodes yet'**
  String get noNotesYet;

  /// No description provided for @tapPencilToAdd.
  ///
  /// In en, this message translates to:
  /// **'Tap the pencil to add one.'**
  String get tapPencilToAdd;

  /// No description provided for @noCardsYet.
  ///
  /// In en, this message translates to:
  /// **'No sparks yet'**
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
  /// **'Empty node'**
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
  /// **'NODES'**
  String get sectionNotes;

  /// No description provided for @sectionCards.
  ///
  /// In en, this message translates to:
  /// **'SPARKS'**
  String get sectionCards;

  /// No description provided for @sectionFolders.
  ///
  /// In en, this message translates to:
  /// **'FOLDS'**
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

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move to fold'**
  String get move;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 selected} other{{n} selected}}'**
  String selectedCount(int n);

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to fold'**
  String get moveToFolder;

  /// No description provided for @deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete?'**
  String get deleteTitle;

  /// No description provided for @deleteItemsConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This will move to Recently deleted, where it stays for 30 days.} other{These {count} items will move to Recently deleted, where they stay for 30 days.}}'**
  String deleteItemsConfirm(int count);

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
  /// **'Create a fold and move this into it'**
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
  /// **'No fold'**
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
  /// **'No folds yet, create one in Cortex.'**
  String get noFoldersYetCreate;

  /// No description provided for @noFoldersYet.
  ///
  /// In en, this message translates to:
  /// **'No folds yet'**
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
  /// **'New fold'**
  String get newSpace;

  /// No description provided for @editSpace.
  ///
  /// In en, this message translates to:
  /// **'Edit fold'**
  String get editSpace;

  /// No description provided for @spaceName.
  ///
  /// In en, this message translates to:
  /// **'Fold name'**
  String get spaceName;

  /// No description provided for @folderColor.
  ///
  /// In en, this message translates to:
  /// **'Fold colour'**
  String get folderColor;

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
  /// **'Archive fold'**
  String get archiveFolder;

  /// No description provided for @archiveFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hidden from Cortex; contents stay put'**
  String get archiveFolderSubtitle;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete fold'**
  String get deleteFolder;

  /// No description provided for @folderArchived.
  ///
  /// In en, this message translates to:
  /// **'Fold archived'**
  String get folderArchived;

  /// No description provided for @addToName.
  ///
  /// In en, this message translates to:
  /// **'Add to {name}'**
  String addToName(String name);

  /// No description provided for @addRemoveHint.
  ///
  /// In en, this message translates to:
  /// **'Tap an item to add or remove it from this fold.'**
  String get addRemoveHint;

  /// No description provided for @noNotesOrCards.
  ///
  /// In en, this message translates to:
  /// **'No nodes or sparks yet.'**
  String get noNotesOrCards;

  /// No description provided for @addExisting.
  ///
  /// In en, this message translates to:
  /// **'Add existing'**
  String get addExisting;

  /// No description provided for @nothingInFolder.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this fold yet'**
  String get nothingInFolder;

  /// No description provided for @useButtonsToAdd.
  ///
  /// In en, this message translates to:
  /// **'Use the + buttons to add a node or existing items.'**
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
  /// **'Node background'**
  String get noteBackground;

  /// No description provided for @copyNote.
  ///
  /// In en, this message translates to:
  /// **'Copy node'**
  String get copyNote;

  /// No description provided for @noteCopied.
  ///
  /// In en, this message translates to:
  /// **'Node copied to clipboard'**
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

  /// No description provided for @strikethrough.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get strikethrough;

  /// No description provided for @highlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlight;

  /// No description provided for @quote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get quote;

  /// No description provided for @indentDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease indent'**
  String get indentDecrease;

  /// No description provided for @indentIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase indent'**
  String get indentIncrease;

  /// No description provided for @alignLeft.
  ///
  /// In en, this message translates to:
  /// **'Align left'**
  String get alignLeft;

  /// No description provided for @alignCenter.
  ///
  /// In en, this message translates to:
  /// **'Align centre'**
  String get alignCenter;

  /// No description provided for @alignRight.
  ///
  /// In en, this message translates to:
  /// **'Align right'**
  String get alignRight;

  /// No description provided for @justify.
  ///
  /// In en, this message translates to:
  /// **'Justify'**
  String get justify;

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
  /// **'Delete spark'**
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
  /// **'Long-press a node, spark or fold to archive it.'**
  String get archiveHint;

  /// No description provided for @longPressToRestore.
  ///
  /// In en, this message translates to:
  /// **'Long-press anything to restore it.'**
  String get longPressToRestore;

  /// No description provided for @noteUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Node unarchived'**
  String get noteUnarchived;

  /// No description provided for @cardUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Spark unarchived'**
  String get cardUnarchived;

  /// No description provided for @folderUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Fold unarchived'**
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
  /// **'All nodes, sparks and folds here are permanently deleted.'**
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

  /// No description provided for @feedBackgroundSection.
  ///
  /// In en, this message translates to:
  /// **'Feed background'**
  String get feedBackgroundSection;

  /// No description provided for @feedBackgroundLabel.
  ///
  /// In en, this message translates to:
  /// **'Home feed background'**
  String get feedBackgroundLabel;

  /// No description provided for @feedBackgroundChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get feedBackgroundChoose;

  /// No description provided for @feedBackgroundLightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode image'**
  String get feedBackgroundLightMode;

  /// No description provided for @feedBackgroundDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode image'**
  String get feedBackgroundDarkMode;

  /// No description provided for @feedBackgroundReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get feedBackgroundReset;

  /// No description provided for @fontsSection.
  ///
  /// In en, this message translates to:
  /// **'Fonts'**
  String get fontsSection;

  /// No description provided for @bodyFontLabel.
  ///
  /// In en, this message translates to:
  /// **'Node & spark body'**
  String get bodyFontLabel;

  /// No description provided for @bodyFontPreview.
  ///
  /// In en, this message translates to:
  /// **'The quick brown fox jumps over the lazy dog.'**
  String get bodyFontPreview;

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
  /// **'Keep your nodes safe'**
  String get backupReminderTitle;

  /// No description provided for @backupReminderBody.
  ///
  /// In en, this message translates to:
  /// **'Back up now so a lost phone doesn\'t mean lost nodes.'**
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

  /// No description provided for @load.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// No description provided for @linksSection.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get linksSection;

  /// No description provided for @mentionedIn.
  ///
  /// In en, this message translates to:
  /// **'Mentioned in {count, plural, =1{1 place} other{{count} places}}'**
  String mentionedIn(int count);

  /// No description provided for @untitledNote.
  ///
  /// In en, this message translates to:
  /// **'Untitled node'**
  String get untitledNote;

  /// No description provided for @linkToNote.
  ///
  /// In en, this message translates to:
  /// **'Link to a node'**
  String get linkToNote;

  /// No description provided for @mentionNodeHeader.
  ///
  /// In en, this message translates to:
  /// **'Link a node'**
  String get mentionNodeHeader;

  /// No description provided for @mentionThreadHeader.
  ///
  /// In en, this message translates to:
  /// **'Mention a thread or impulse'**
  String get mentionThreadHeader;

  /// No description provided for @searchOrCreateNote.
  ///
  /// In en, this message translates to:
  /// **'Search or type a new title'**
  String get searchOrCreateNote;

  /// No description provided for @createNoteNamed.
  ///
  /// In en, this message translates to:
  /// **'Create \"{name}\"'**
  String createNoteNamed(String name);

  /// No description provided for @noNotesToLink.
  ///
  /// In en, this message translates to:
  /// **'No nodes to link yet'**
  String get noNotesToLink;

  /// No description provided for @tapNoteThenLink.
  ///
  /// In en, this message translates to:
  /// **'Tap in the node first, then add a link'**
  String get tapNoteThenLink;

  /// No description provided for @journalSection.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journalSection;

  /// No description provided for @journalReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily journal nudge'**
  String get journalReminderTitle;

  /// No description provided for @journalReminderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A gentle reminder to write each evening'**
  String get journalReminderSubtitle;

  /// No description provided for @journalReminderTime.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get journalReminderTime;

  /// No description provided for @journalYearEntries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No entries yet} =1{1 entry this year} other{{count} entries this year}}'**
  String journalYearEntries(int count);

  /// No description provided for @heatmapLess.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get heatmapLess;

  /// No description provided for @heatmapMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get heatmapMore;

  /// No description provided for @versionHistory.
  ///
  /// In en, this message translates to:
  /// **'Version history'**
  String get versionHistory;

  /// No description provided for @versionsSaved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 saved} other{{count} saved}}'**
  String versionsSaved(int count);

  /// No description provided for @saveVersion.
  ///
  /// In en, this message translates to:
  /// **'Save version'**
  String get saveVersion;

  /// No description provided for @versionSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Version saved'**
  String get versionSavedToast;

  /// No description provided for @versionHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No versions yet'**
  String get versionHistoryEmpty;

  /// No description provided for @versionHistoryEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Save a version to snapshot this chapter, a heavy revise stays reversible.'**
  String get versionHistoryEmptyBody;

  /// No description provided for @versionCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get versionCurrent;

  /// No description provided for @versionAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get versionAuto;

  /// No description provided for @versionSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get versionSaved;

  /// No description provided for @versionNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get versionNow;

  /// No description provided for @versionJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get versionJustNow;

  /// No description provided for @versionToday.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String versionToday(String time);

  /// No description provided for @versionYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String versionYesterday(String time);

  /// No description provided for @restoreVersion.
  ///
  /// In en, this message translates to:
  /// **'Restore this version'**
  String get restoreVersion;

  /// No description provided for @restoreVersionBody.
  ///
  /// In en, this message translates to:
  /// **'Your current text is saved as a version first, so you can undo this.'**
  String get restoreVersionBody;

  /// No description provided for @versionRestoredToast.
  ///
  /// In en, this message translates to:
  /// **'Version restored'**
  String get versionRestoredToast;

  /// No description provided for @tabReflexes.
  ///
  /// In en, this message translates to:
  /// **'Reflexes'**
  String get tabReflexes;

  /// No description provided for @newImpulse.
  ///
  /// In en, this message translates to:
  /// **'New impulse'**
  String get newImpulse;

  /// No description provided for @editImpulse.
  ///
  /// In en, this message translates to:
  /// **'Edit impulse'**
  String get editImpulse;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @reflexesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No impulses yet'**
  String get reflexesEmpty;

  /// No description provided for @reflexesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'An impulse is a project made of small threads you tick off. Start one to build momentum.'**
  String get reflexesEmptyBody;

  /// No description provided for @untitledImpulse.
  ///
  /// In en, this message translates to:
  /// **'Untitled impulse'**
  String get untitledImpulse;

  /// No description provided for @todayLabel.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayLabel;

  /// No description provided for @overallLabel.
  ///
  /// In en, this message translates to:
  /// **'Overall'**
  String get overallLabel;

  /// No description provided for @impulseTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get impulseTitle;

  /// No description provided for @impulseTitleHint.
  ///
  /// In en, this message translates to:
  /// **'What\'s the project?'**
  String get impulseTitleHint;

  /// No description provided for @impulseGoal.
  ///
  /// In en, this message translates to:
  /// **'What will you achieve?'**
  String get impulseGoal;

  /// No description provided for @impulseGoalHint.
  ///
  /// In en, this message translates to:
  /// **'The goal you\'re chasing'**
  String get impulseGoalHint;

  /// No description provided for @impulseCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get impulseCategory;

  /// No description provided for @impulseCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Work, Personal'**
  String get impulseCategoryHint;

  /// No description provided for @categoryWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get categoryWork;

  /// No description provided for @categoryPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get categoryPersonal;

  /// No description provided for @impulseMode.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get impulseMode;

  /// No description provided for @modeDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get modeDaily;

  /// No description provided for @modeDailyDesc.
  ///
  /// In en, this message translates to:
  /// **'Threads reset each day, track today\'s progress'**
  String get modeDailyDesc;

  /// No description provided for @modeChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get modeChecklist;

  /// No description provided for @modeChecklistDesc.
  ///
  /// In en, this message translates to:
  /// **'Tick threads off once, fill toward 100%'**
  String get modeChecklistDesc;

  /// No description provided for @modeLongTerm.
  ///
  /// In en, this message translates to:
  /// **'Long-term'**
  String get modeLongTerm;

  /// No description provided for @modeLongTermDesc.
  ///
  /// In en, this message translates to:
  /// **'A goal split into sections and modules, plus a daily reminder list'**
  String get modeLongTermDesc;

  /// No description provided for @impulseStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get impulseStartDate;

  /// No description provided for @noStartDate.
  ///
  /// In en, this message translates to:
  /// **'No start date'**
  String get noStartDate;

  /// No description provided for @impulseDeadline.
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get impulseDeadline;

  /// No description provided for @noDeadline.
  ///
  /// In en, this message translates to:
  /// **'No deadline'**
  String get noDeadline;

  /// No description provided for @datesSection.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get datesSection;

  /// No description provided for @startShort.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get startShort;

  /// No description provided for @dueShort.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get dueShort;

  /// No description provided for @setDates.
  ///
  /// In en, this message translates to:
  /// **'Set dates'**
  String get setDates;

  /// No description provided for @clearDatesAction.
  ///
  /// In en, this message translates to:
  /// **'Clear dates'**
  String get clearDatesAction;

  /// No description provided for @heatmapDaysDone.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} days done'**
  String heatmapDaysDone(int done, int total);

  /// No description provided for @heatmapDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days} days left'**
  String heatmapDaysLeft(int days);

  /// No description provided for @consistency.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get consistency;

  /// No description provided for @consistencyHint.
  ///
  /// In en, this message translates to:
  /// **'Which days do you work on this?'**
  String get consistencyHint;

  /// No description provided for @threadsSection.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get threadsSection;

  /// No description provided for @noThreads.
  ///
  /// In en, this message translates to:
  /// **'No threads yet, add the first one below.'**
  String get noThreads;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @addSection.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get addSection;

  /// No description provided for @sectionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Year 1'**
  String get sectionHint;

  /// No description provided for @addSubsection.
  ///
  /// In en, this message translates to:
  /// **'Add module'**
  String get addSubsection;

  /// No description provided for @subjectHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Calculus'**
  String get subjectHint;

  /// No description provided for @sectionsHeader.
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get sectionsHeader;

  /// No description provided for @dailyReminder.
  ///
  /// In en, this message translates to:
  /// **'Random Threads'**
  String get dailyReminder;

  /// No description provided for @untitledSection.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitledSection;

  /// No description provided for @addThreadHint.
  ///
  /// In en, this message translates to:
  /// **'New thread…'**
  String get addThreadHint;

  /// No description provided for @deleteImpulse.
  ///
  /// In en, this message translates to:
  /// **'Delete impulse'**
  String get deleteImpulse;

  /// No description provided for @deleteImpulseConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this impulse and all its threads?'**
  String get deleteImpulseConfirm;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @daysLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Due today} =1{1 day left} other{{count} days left}}'**
  String daysLeft(int count);

  /// No description provided for @onThisDay.
  ///
  /// In en, this message translates to:
  /// **'On this day'**
  String get onThisDay;

  /// No description provided for @onThisDayYearsAgo.
  ///
  /// In en, this message translates to:
  /// **'{years, plural, =1{1 year ago} other{{years} years ago}}'**
  String onThisDayYearsAgo(int years);

  /// No description provided for @saveToDevice.
  ///
  /// In en, this message translates to:
  /// **'Save to device or Drive'**
  String get saveToDevice;

  /// No description provided for @saveToDeviceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Write the .zip to Files, Drive, an SD card…'**
  String get saveToDeviceSubtitle;

  /// No description provided for @backupSavedToDevice.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupSavedToDevice;

  /// No description provided for @loadSampleData.
  ///
  /// In en, this message translates to:
  /// **'Load sample data'**
  String get loadSampleData;

  /// No description provided for @loadSampleDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add demo nodes, sparks and a short book'**
  String get loadSampleDataSubtitle;

  /// No description provided for @sampleDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Load sample data?'**
  String get sampleDataTitle;

  /// No description provided for @sampleDataBody.
  ///
  /// In en, this message translates to:
  /// **'This adds a set of demo nodes, saved sparks and a short book so you can try everything out. It won\'t touch what you already have.'**
  String get sampleDataBody;

  /// No description provided for @sampleDataLoaded.
  ///
  /// In en, this message translates to:
  /// **'Sample data added'**
  String get sampleDataLoaded;

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
  /// **'This replaces your current nodes, sparks and folds with the ones in the backup.'**
  String get restoreBackupBody;

  /// No description provided for @storageSection.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageSection;

  /// No description provided for @statNotes.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get statNotes;

  /// No description provided for @statCortex.
  ///
  /// In en, this message translates to:
  /// **'Cortex'**
  String get statCortex;

  /// No description provided for @statCards.
  ///
  /// In en, this message translates to:
  /// **'Sparks'**
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
  /// **'This permanently deletes every node, fold and spark on this device.'**
  String get clearAllDataBody;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @aboutLine.
  ///
  /// In en, this message translates to:
  /// **'A notes app · v1.0'**
  String get aboutLine;

  /// No description provided for @savedToCards.
  ///
  /// In en, this message translates to:
  /// **'Saved to Sparks'**
  String get savedToCards;

  /// No description provided for @savedToNotes.
  ///
  /// In en, this message translates to:
  /// **'Saved to Nodes'**
  String get savedToNotes;

  /// No description provided for @saveToBraim.
  ///
  /// In en, this message translates to:
  /// **'Save to Braim'**
  String get saveToBraim;

  /// No description provided for @saveNoteToBraim.
  ///
  /// In en, this message translates to:
  /// **'Save node to Braim'**
  String get saveNoteToBraim;

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
  /// **'Fold name'**
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

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreOptions;

  /// No description provided for @chooseTheme.
  ///
  /// In en, this message translates to:
  /// **'Colour & background'**
  String get chooseTheme;

  /// No description provided for @createNote.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get createNote;

  /// No description provided for @editAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your nodes sync automatically and stay available everywhere.'**
  String get signInSubtitle;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nodes stay on this device and stop syncing.'**
  String get signOutSubtitle;

  /// No description provided for @syncOn.
  ///
  /// In en, this message translates to:
  /// **'Syncing automatically'**
  String get syncOn;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in didn\'t work. Check your connection and try again.'**
  String get signInFailed;

  /// No description provided for @syncNudgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep your nodes everywhere'**
  String get syncNudgeTitle;

  /// No description provided for @syncNudgeBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google and every node syncs by itself.'**
  String get syncNudgeBody;

  /// No description provided for @syncNudgeAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get syncNudgeAction;

  /// No description provided for @switchAccount.
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get switchAccount;

  /// No description provided for @theBooks.
  ///
  /// In en, this message translates to:
  /// **'The Books'**
  String get theBooks;

  /// No description provided for @journalTab.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journalTab;

  /// No description provided for @booksEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing on the shelf yet'**
  String get booksEmptyTitle;

  /// No description provided for @booksEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the pencil to start your first book.'**
  String get booksEmptyBody;

  /// No description provided for @somethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get somethingWrong;

  /// No description provided for @newBook.
  ///
  /// In en, this message translates to:
  /// **'New book'**
  String get newBook;

  /// No description provided for @bookTitle.
  ///
  /// In en, this message translates to:
  /// **'Book title'**
  String get bookTitle;

  /// No description provided for @untitledBook.
  ///
  /// In en, this message translates to:
  /// **'Untitled book'**
  String get untitledBook;

  /// No description provided for @contentsPage.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get contentsPage;

  /// No description provided for @addChapter.
  ///
  /// In en, this message translates to:
  /// **'Add chapter'**
  String get addChapter;

  /// No description provided for @addPage.
  ///
  /// In en, this message translates to:
  /// **'Add page'**
  String get addPage;

  /// No description provided for @shareAsPdf.
  ///
  /// In en, this message translates to:
  /// **'Share as PDF'**
  String get shareAsPdf;

  /// No description provided for @deleteBook.
  ///
  /// In en, this message translates to:
  /// **'Delete book'**
  String get deleteBook;

  /// No description provided for @deletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete page'**
  String get deletePage;

  /// No description provided for @changeCover.
  ///
  /// In en, this message translates to:
  /// **'Change cover'**
  String get changeCover;

  /// No description provided for @renameBook.
  ///
  /// In en, this message translates to:
  /// **'Rename book'**
  String get renameBook;

  /// No description provided for @chooseFont.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get chooseFont;

  /// No description provided for @pageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {n}'**
  String pageLabel(int n);

  /// No description provided for @confirmDeleteBook.
  ///
  /// In en, this message translates to:
  /// **'Delete this book and all its pages? This can\'t be undone.'**
  String get confirmDeleteBook;

  /// No description provided for @bookDescription.
  ///
  /// In en, this message translates to:
  /// **'Book description'**
  String get bookDescription;

  /// No description provided for @addDescription.
  ///
  /// In en, this message translates to:
  /// **'Add a short description'**
  String get addDescription;

  /// No description provided for @editDescription.
  ///
  /// In en, this message translates to:
  /// **'Edit description'**
  String get editDescription;

  /// No description provided for @byAuthor.
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String byAuthor(String name);

  /// No description provided for @readBook.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get readBook;

  /// No description provided for @contentsSection.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get contentsSection;

  /// No description provided for @wordsCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 word} other{{n} words}}'**
  String wordsCount(int n);

  /// No description provided for @chaptersCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 chapter} other{{n} chapters}}'**
  String chaptersCount(int n);

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @statusRevised.
  ///
  /// In en, this message translates to:
  /// **'Revised'**
  String get statusRevised;

  /// No description provided for @statusFinal.
  ///
  /// In en, this message translates to:
  /// **'Final'**
  String get statusFinal;

  /// No description provided for @statusNone.
  ///
  /// In en, this message translates to:
  /// **'No tag'**
  String get statusNone;

  /// No description provided for @chapterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get chapterStatus;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @exportPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get exportPdf;

  /// No description provided for @exportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get exportMarkdown;

  /// No description provided for @exportEpub.
  ///
  /// In en, this message translates to:
  /// **'ePub'**
  String get exportEpub;

  /// No description provided for @pageNOfM.
  ///
  /// In en, this message translates to:
  /// **'Page {n} of {m}'**
  String pageNOfM(int n, int m);

  /// No description provided for @dragToReorder.
  ///
  /// In en, this message translates to:
  /// **'Hold and drag to reorder'**
  String get dragToReorder;

  /// No description provided for @reorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @statMostActive.
  ///
  /// In en, this message translates to:
  /// **'Most active time'**
  String get statMostActive;

  /// No description provided for @statTotalEntries.
  ///
  /// In en, this message translates to:
  /// **'Total entries'**
  String get statTotalEntries;

  /// No description provided for @statLongestEntry.
  ///
  /// In en, this message translates to:
  /// **'Longest word count'**
  String get statLongestEntry;

  /// No description provided for @statTotalBooks.
  ///
  /// In en, this message translates to:
  /// **'Total books'**
  String get statTotalBooks;

  /// No description provided for @statPagesWritten.
  ///
  /// In en, this message translates to:
  /// **'Pages written'**
  String get statPagesWritten;

  /// No description provided for @statWordsWritten.
  ///
  /// In en, this message translates to:
  /// **'Words written'**
  String get statWordsWritten;

  /// No description provided for @readerSettings.
  ///
  /// In en, this message translates to:
  /// **'Themes & Settings'**
  String get readerSettings;

  /// No description provided for @highlightsAndNotes.
  ///
  /// In en, this message translates to:
  /// **'Highlights & nodes'**
  String get highlightsAndNotes;

  /// No description provided for @noHighlightsYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing highlighted yet. Select any text while reading.'**
  String get noHighlightsYet;

  /// No description provided for @annotateNote.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get annotateNote;

  /// No description provided for @annotateHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get annotateHighlight;

  /// No description provided for @translate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translate;

  /// No description provided for @dictionary.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get dictionary;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @noteHint.
  ///
  /// In en, this message translates to:
  /// **'What do you make of it?'**
  String get noteHint;

  /// No description provided for @bookAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get bookAuthor;

  /// No description provided for @setAuthor.
  ///
  /// In en, this message translates to:
  /// **'Set author'**
  String get setAuthor;

  /// No description provided for @authorHint.
  ///
  /// In en, this message translates to:
  /// **'Who\'s writing this?'**
  String get authorHint;

  /// No description provided for @bookFont.
  ///
  /// In en, this message translates to:
  /// **'Typeface'**
  String get bookFont;

  /// No description provided for @bookFontTitle.
  ///
  /// In en, this message translates to:
  /// **'Book typeface'**
  String get bookFontTitle;

  /// No description provided for @bookFontSample.
  ///
  /// In en, this message translates to:
  /// **'The quick brown fox jumps over the lazy dog.'**
  String get bookFontSample;

  /// No description provided for @bookNotesSection.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get bookNotesSection;

  /// No description provided for @bookNoteAdd.
  ///
  /// In en, this message translates to:
  /// **'New node'**
  String get bookNoteAdd;

  /// No description provided for @bookNotesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Jot down characters, places and plot ideas here. They stay out of the manuscript.'**
  String get bookNotesEmpty;

  /// No description provided for @bookNoteUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled node'**
  String get bookNoteUntitled;

  /// No description provided for @bookNoteDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete node'**
  String get bookNoteDelete;

  /// No description provided for @linkToChapter.
  ///
  /// In en, this message translates to:
  /// **'Link to chapter'**
  String get linkToChapter;

  /// No description provided for @unlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get unlink;

  /// No description provided for @statWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get statWords;

  /// No description provided for @statCharacters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get statCharacters;

  /// No description provided for @statMinRead.
  ///
  /// In en, this message translates to:
  /// **'Min read'**
  String get statMinRead;

  /// No description provided for @wordTarget.
  ///
  /// In en, this message translates to:
  /// **'Word target'**
  String get wordTarget;

  /// No description provided for @wordTargetHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 2000 (0 to clear)'**
  String get wordTargetHint;

  /// No description provided for @addFrontBackMatter.
  ///
  /// In en, this message translates to:
  /// **'Add front/back matter'**
  String get addFrontBackMatter;

  /// No description provided for @matterDedication.
  ///
  /// In en, this message translates to:
  /// **'Dedication'**
  String get matterDedication;

  /// No description provided for @matterEpigraph.
  ///
  /// In en, this message translates to:
  /// **'Epigraph'**
  String get matterEpigraph;

  /// No description provided for @matterAcknowledgements.
  ///
  /// In en, this message translates to:
  /// **'Acknowledgements'**
  String get matterAcknowledgements;

  /// No description provided for @findAndReplace.
  ///
  /// In en, this message translates to:
  /// **'Find & replace'**
  String get findAndReplace;

  /// No description provided for @findLabel.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get findLabel;

  /// No description provided for @replaceWithLabel.
  ///
  /// In en, this message translates to:
  /// **'Replace with'**
  String get replaceWithLabel;

  /// No description provided for @caseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Case sensitive'**
  String get caseSensitive;

  /// No description provided for @replaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace all'**
  String get replaceAll;

  /// No description provided for @matchesFound.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =0{No matches} =1{1 match} other{{n} matches}}'**
  String matchesFound(int n);

  /// No description provided for @replaceAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{Replace 1 occurrence across the book?} other{Replace {n} occurrences across the book?}}'**
  String replaceAllConfirm(int n);

  /// No description provided for @replacedCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =0{Nothing replaced} =1{1 replacement made} other{{n} replacements made}}'**
  String replacedCount(int n);

  /// No description provided for @searchChapters.
  ///
  /// In en, this message translates to:
  /// **'Search chapters'**
  String get searchChapters;

  /// No description provided for @noChaptersMatch.
  ///
  /// In en, this message translates to:
  /// **'No chapters match'**
  String get noChaptersMatch;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @bookmarkThisSpot.
  ///
  /// In en, this message translates to:
  /// **'Bookmark this spot'**
  String get bookmarkThisSpot;

  /// No description provided for @bookmarkAdded.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked'**
  String get bookmarkAdded;

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet. Tap the bookmark icon while reading.'**
  String get noBookmarks;

  /// No description provided for @bookmarkAt.
  ///
  /// In en, this message translates to:
  /// **'At {pct}%'**
  String bookmarkAt(int pct);

  /// No description provided for @holdForCalendar.
  ///
  /// In en, this message translates to:
  /// **'Hold the week for the calendar'**
  String get holdForCalendar;

  /// No description provided for @dailyDay.
  ///
  /// In en, this message translates to:
  /// **'Your daily day'**
  String get dailyDay;

  /// No description provided for @dailyDayAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to your day…'**
  String get dailyDayAdd;

  /// No description provided for @dailyDayEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing planned yet'**
  String get dailyDayEmpty;

  /// No description provided for @dailyDaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to plan and tick off your day'**
  String get dailyDaySubtitle;

  /// No description provided for @reflexes.
  ///
  /// In en, this message translates to:
  /// **'Reflexes'**
  String get reflexes;

  /// No description provided for @pauseImpulse.
  ///
  /// In en, this message translates to:
  /// **'Pause impulse'**
  String get pauseImpulse;

  /// No description provided for @resumeImpulse.
  ///
  /// In en, this message translates to:
  /// **'Resume impulse'**
  String get resumeImpulse;

  /// No description provided for @markComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark as complete'**
  String get markComplete;

  /// No description provided for @markActive.
  ///
  /// In en, this message translates to:
  /// **'Mark as active'**
  String get markActive;

  /// No description provided for @pinToFeed.
  ///
  /// In en, this message translates to:
  /// **'Pin to journal'**
  String get pinToFeed;

  /// No description provided for @unpinFromFeed.
  ///
  /// In en, this message translates to:
  /// **'Unpin from journal'**
  String get unpinFromFeed;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statusPaused;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @archiveImpulse.
  ///
  /// In en, this message translates to:
  /// **'Archive impulse'**
  String get archiveImpulse;

  /// No description provided for @unarchiveImpulse.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchiveImpulse;

  /// No description provided for @sortByPriority.
  ///
  /// In en, this message translates to:
  /// **'Sort by priority'**
  String get sortByPriority;

  /// No description provided for @filterActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get filterActive;

  /// No description provided for @filterDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get filterDone;

  /// No description provided for @filterArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get filterArchived;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @pomodoro.
  ///
  /// In en, this message translates to:
  /// **'Pomodoro'**
  String get pomodoro;

  /// No description provided for @focusTimer.
  ///
  /// In en, this message translates to:
  /// **'Focus timer'**
  String get focusTimer;

  /// No description provided for @focusTitle.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get focusTitle;

  /// No description provided for @pomodoroStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get pomodoroStart;

  /// No description provided for @pomodoroPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pomodoroPause;

  /// No description provided for @pomodoroResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get pomodoroResume;

  /// No description provided for @pomodoroFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get pomodoroFocus;

  /// No description provided for @pomodoroBreak.
  ///
  /// In en, this message translates to:
  /// **'Break'**
  String get pomodoroBreak;

  /// No description provided for @pomodoroComplete.
  ///
  /// In en, this message translates to:
  /// **'All done'**
  String get pomodoroComplete;

  /// No description provided for @pomodoroFocusMin.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get pomodoroFocusMin;

  /// No description provided for @pomodoroBreakMin.
  ///
  /// In en, this message translates to:
  /// **'Break'**
  String get pomodoroBreakMin;

  /// No description provided for @pomodoroRounds.
  ///
  /// In en, this message translates to:
  /// **'Rounds'**
  String get pomodoroRounds;

  /// No description provided for @pomodoroRound.
  ///
  /// In en, this message translates to:
  /// **'Round'**
  String get pomodoroRound;

  /// No description provided for @pomodoroPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get pomodoroPaused;

  /// No description provided for @pomodoroBreakSoon.
  ///
  /// In en, this message translates to:
  /// **'Break time'**
  String get pomodoroBreakSoon;

  /// No description provided for @pomodoroBackToFocus.
  ///
  /// In en, this message translates to:
  /// **'Back to focus'**
  String get pomodoroBackToFocus;

  /// No description provided for @pomodoroSessionDone.
  ///
  /// In en, this message translates to:
  /// **'Focus session complete'**
  String get pomodoroSessionDone;

  /// No description provided for @pomodoroSettings.
  ///
  /// In en, this message translates to:
  /// **'Focus setup'**
  String get pomodoroSettings;

  /// No description provided for @pomodoroEnd.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get pomodoroEnd;

  /// No description provided for @focusRunningHint.
  ///
  /// In en, this message translates to:
  /// **'Timer keeps running in the background, you can leave'**
  String get focusRunningHint;

  /// No description provided for @dndTitle.
  ///
  /// In en, this message translates to:
  /// **'Do Not Disturb'**
  String get dndTitle;

  /// No description provided for @dndOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get dndOff;

  /// No description provided for @dndOffDesc.
  ///
  /// In en, this message translates to:
  /// **'Notifications stay on'**
  String get dndOffDesc;

  /// No description provided for @dndFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get dndFocus;

  /// No description provided for @dndFocusDesc.
  ///
  /// In en, this message translates to:
  /// **'Silence notifications; calls still show, no ring'**
  String get dndFocusDesc;

  /// No description provided for @dndSilence.
  ///
  /// In en, this message translates to:
  /// **'Total silence'**
  String get dndSilence;

  /// No description provided for @dndSilenceDesc.
  ///
  /// In en, this message translates to:
  /// **'Silence everything, calls included'**
  String get dndSilenceDesc;

  /// No description provided for @dndGrantTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow Do Not Disturb?'**
  String get dndGrantTitle;

  /// No description provided for @dndGrantBody.
  ///
  /// In en, this message translates to:
  /// **'Braim needs one-time Do Not Disturb access to mute your phone during focus. Nothing is read.'**
  String get dndGrantBody;

  /// No description provided for @dndGrant.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get dndGrant;

  /// No description provided for @dndCallsNote.
  ///
  /// In en, this message translates to:
  /// **'Calls always appear silently from the top, pick Total silence to hide them too.'**
  String get dndCallsNote;

  /// No description provided for @moveTask.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveTask;

  /// No description provided for @moveTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to reflex'**
  String get moveTaskTitle;

  /// No description provided for @dayComplete.
  ///
  /// In en, this message translates to:
  /// **'All done for today!'**
  String get dayComplete;

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1-day streak} other{{count}-day streak}}'**
  String streakDays(int count);

  /// No description provided for @streakBest.
  ///
  /// In en, this message translates to:
  /// **'best {count}'**
  String streakBest(int count);

  /// No description provided for @restDay.
  ///
  /// In en, this message translates to:
  /// **'Rest day'**
  String get restDay;

  /// No description provided for @todaysProgress.
  ///
  /// In en, this message translates to:
  /// **'Today\'s progress'**
  String get todaysProgress;

  /// No description provided for @progressTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get progressTotal;

  /// No description provided for @progressCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get progressCompleted;

  /// No description provided for @progressPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get progressPending;

  /// No description provided for @progressAllClear.
  ///
  /// In en, this message translates to:
  /// **'Nothing due today'**
  String get progressAllClear;

  /// No description provided for @perfectDay.
  ///
  /// In en, this message translates to:
  /// **'Perfect day'**
  String get perfectDay;

  /// No description provided for @nextUp.
  ///
  /// In en, this message translates to:
  /// **'Next up'**
  String get nextUp;

  /// No description provided for @analyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analyticsTitle;

  /// No description provided for @analyticsCurrentStreak.
  ///
  /// In en, this message translates to:
  /// **'Current streak'**
  String get analyticsCurrentStreak;

  /// No description provided for @analyticsBestStreak.
  ///
  /// In en, this message translates to:
  /// **'Best streak'**
  String get analyticsBestStreak;

  /// No description provided for @analyticsThreads.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get analyticsThreads;

  /// No description provided for @analyticsActiveDays.
  ///
  /// In en, this message translates to:
  /// **'Active days'**
  String get analyticsActiveDays;

  /// No description provided for @analyticsWritingTime.
  ///
  /// In en, this message translates to:
  /// **'Time writing'**
  String get analyticsWritingTime;

  /// No description provided for @analyticsAllReflexes.
  ///
  /// In en, this message translates to:
  /// **'All reflexes'**
  String get analyticsAllReflexes;

  /// No description provided for @analyticsScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get analyticsScopeAll;

  /// No description provided for @analyticsConsistency.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get analyticsConsistency;

  /// No description provided for @analyticsPeriodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get analyticsPeriodToday;

  /// No description provided for @analyticsPeriodWeek.
  ///
  /// In en, this message translates to:
  /// **'1W'**
  String get analyticsPeriodWeek;

  /// No description provided for @analyticsPeriodMonth.
  ///
  /// In en, this message translates to:
  /// **'1M'**
  String get analyticsPeriodMonth;

  /// No description provided for @analyticsPeriodYear.
  ///
  /// In en, this message translates to:
  /// **'1Y'**
  String get analyticsPeriodYear;

  /// No description provided for @analyticsPeriodAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get analyticsPeriodAll;

  /// No description provided for @analyticsPeriodMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get analyticsPeriodMax;

  /// No description provided for @analyticsAllImpulses.
  ///
  /// In en, this message translates to:
  /// **'All impulses'**
  String get analyticsAllImpulses;

  /// No description provided for @analyticsTrackLabel.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get analyticsTrackLabel;

  /// No description provided for @analyticsAverage.
  ///
  /// In en, this message translates to:
  /// **'Average progress'**
  String get analyticsAverage;

  /// No description provided for @analyticsMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get analyticsMissed;

  /// No description provided for @proceed.
  ///
  /// In en, this message translates to:
  /// **'Proceed'**
  String get proceed;

  /// No description provided for @editPastTitle.
  ///
  /// In en, this message translates to:
  /// **'Editing a past day'**
  String get editPastTitle;

  /// No description provided for @editPastBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re changing a task in the past. Are you sure you want to proceed?'**
  String get editPastBody;

  /// No description provided for @editFutureTitle.
  ///
  /// In en, this message translates to:
  /// **'Editing a future day'**
  String get editFutureTitle;

  /// No description provided for @editFutureBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re changing a task in the future. Are you sure you want to proceed?'**
  String get editFutureBody;

  /// No description provided for @analyticsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Deeper analytics, trends, per-thread breakdowns and more, are coming soon.'**
  String get analyticsComingSoon;

  /// No description provided for @pickProgressImpulse.
  ///
  /// In en, this message translates to:
  /// **'Track progress for'**
  String get pickProgressImpulse;

  /// No description provided for @combinedProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'All reflexes today'**
  String get combinedProgressLabel;

  /// No description provided for @cropTitle.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get cropTitle;

  /// No description provided for @cropReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get cropReset;

  /// No description provided for @cropFreeform.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get cropFreeform;

  /// No description provided for @cropSquare.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get cropSquare;

  /// No description provided for @consistencyHeatmap.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get consistencyHeatmap;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyJumpToDate.
  ///
  /// In en, this message translates to:
  /// **'Jump to date'**
  String get historyJumpToDate;

  /// No description provided for @textStyle.
  ///
  /// In en, this message translates to:
  /// **'Text style'**
  String get textStyle;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @resetSize.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetSize;

  /// No description provided for @moveCheckedToBottom.
  ///
  /// In en, this message translates to:
  /// **'Move ticked items to the bottom'**
  String get moveCheckedToBottom;

  /// No description provided for @backgroundForDark.
  ///
  /// In en, this message translates to:
  /// **'Background for dark mode'**
  String get backgroundForDark;

  /// No description provided for @backgroundForLight.
  ///
  /// In en, this message translates to:
  /// **'Background for light mode'**
  String get backgroundForLight;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No task history yet.'**
  String get historyEmpty;

  /// No description provided for @historyNoTasksDay.
  ///
  /// In en, this message translates to:
  /// **'No tasks scheduled this day.'**
  String get historyNoTasksDay;

  /// No description provided for @historyCompletedOf.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} completed'**
  String historyCompletedOf(int done, int total);

  /// No description provided for @rearrangeJournal.
  ///
  /// In en, this message translates to:
  /// **'Rearrange'**
  String get rearrangeJournal;

  /// No description provided for @rearrangeJournalHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder your journal sections.'**
  String get rearrangeJournalHint;

  /// No description provided for @sectionDailyTasks.
  ///
  /// In en, this message translates to:
  /// **'Daily day'**
  String get sectionDailyTasks;

  /// No description provided for @sectionReflexCard.
  ///
  /// In en, this message translates to:
  /// **'Reflexes card'**
  String get sectionReflexCard;

  /// No description provided for @sectionDiaryEntries.
  ///
  /// In en, this message translates to:
  /// **'Diary entries'**
  String get sectionDiaryEntries;

  /// No description provided for @composeDailyTask.
  ///
  /// In en, this message translates to:
  /// **'Add to your daily day'**
  String get composeDailyTask;

  /// No description provided for @composeReflex.
  ///
  /// In en, this message translates to:
  /// **'New reflex'**
  String get composeReflex;

  /// No description provided for @composeEntry.
  ///
  /// In en, this message translates to:
  /// **'New journal entry'**
  String get composeEntry;

  /// No description provided for @reflexesProjects.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No projects} =1{1 project} other{{count} projects}}'**
  String reflexesProjects(int count);

  /// No description provided for @newThread.
  ///
  /// In en, this message translates to:
  /// **'New thread'**
  String get newThread;

  /// No description provided for @taskComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get taskComplete;

  /// No description provided for @taskUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get taskUndo;

  /// No description provided for @taskRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get taskRemove;

  /// No description provided for @important.
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get important;

  /// No description provided for @flagBest.
  ///
  /// In en, this message translates to:
  /// **'Best to have'**
  String get flagBest;

  /// No description provided for @flagOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get flagOptional;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @descriptionAction.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionAction;

  /// No description provided for @startTime.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get endTime;

  /// No description provided for @setTime.
  ///
  /// In en, this message translates to:
  /// **'Set time'**
  String get setTime;

  /// No description provided for @setStartFirst.
  ///
  /// In en, this message translates to:
  /// **'Set start first'**
  String get setStartFirst;

  /// No description provided for @clearTime.
  ///
  /// In en, this message translates to:
  /// **'Clear time'**
  String get clearTime;

  /// No description provided for @changeAllTimes.
  ///
  /// In en, this message translates to:
  /// **'Change all times'**
  String get changeAllTimes;

  /// No description provided for @changeAllTimesHint.
  ///
  /// In en, this message translates to:
  /// **'Apply one time window to every task in this impulse.'**
  String get changeAllTimesHint;

  /// No description provided for @noEndTime.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noEndTime;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @allTimesUpdated.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No tasks to update} =1{1 task moved to the new time} other{{count} tasks moved to the new time}}'**
  String allTimesUpdated(int count);

  /// No description provided for @notifyAtStart.
  ///
  /// In en, this message translates to:
  /// **'Notify me at the start time'**
  String get notifyAtStart;

  /// No description provided for @daysSection.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get daysSection;

  /// No description provided for @daysHint.
  ///
  /// In en, this message translates to:
  /// **'Pick the days this runs on (none = every day).'**
  String get daysHint;

  /// No description provided for @repeatOnce.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get repeatOnce;

  /// No description provided for @repeatEveryday.
  ///
  /// In en, this message translates to:
  /// **'Everyday'**
  String get repeatEveryday;

  /// No description provided for @repeatOnceHint.
  ///
  /// In en, this message translates to:
  /// **'A one-time task. Tick it off and it stays, done, until you delete it.'**
  String get repeatOnceHint;

  /// No description provided for @addLink.
  ///
  /// In en, this message translates to:
  /// **'Add link'**
  String get addLink;

  /// No description provided for @linkLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Label (e.g. Google Meet)'**
  String get linkLabelHint;

  /// No description provided for @locationSection.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationSection;

  /// No description provided for @addLocation.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get addLocation;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get openInMaps;

  /// No description provided for @descriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Add a description…'**
  String get descriptionHint;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask;

  /// No description provided for @inTime.
  ///
  /// In en, this message translates to:
  /// **'In {rel}'**
  String inTime(String rel);

  /// No description provided for @timePassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get timePassed;

  /// No description provided for @removeTaskConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this task?'**
  String get removeTaskConfirm;

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
  /// **'Your notes live on Home. Tap the pencil to write one and it saves as you type. The editor gives you bold, italic, highlight, headings, lists and checklists, and you can add and crop photos or set the text size. Long-press any note for quick actions.'**
  String get tutWelcomeBody;

  /// No description provided for @tutCardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sparks'**
  String get tutCardsTitle;

  /// No description provided for @tutCardsBody.
  ///
  /// In en, this message translates to:
  /// **'Share a link from any app to Braim and it saves as a spark, no app switching. Add your own note under any spark, and duplicates merge on their own. Use the toggle to switch the feed between Open and Blocks views.'**
  String get tutCardsBody;

  /// No description provided for @tutCortexTitle.
  ///
  /// In en, this message translates to:
  /// **'Cortex'**
  String get tutCortexTitle;

  /// No description provided for @tutCortexBody.
  ///
  /// In en, this message translates to:
  /// **'Folders for your notes and sparks. Make one with the plus button, give it a cover photo, and file things from the long-press menu.'**
  String get tutCortexBody;

  /// No description provided for @tutReflexesTitle.
  ///
  /// In en, this message translates to:
  /// **'Reflexes'**
  String get tutReflexesTitle;

  /// No description provided for @tutReflexesBody.
  ///
  /// In en, this message translates to:
  /// **'Build habits and projects as Reflexes. Add daily tasks or one-time ones, tick them off, and watch your streak grow. Tap the heatmap to open the full day-by-day history.'**
  String get tutReflexesBody;

  /// No description provided for @tutBooksTitle.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get tutBooksTitle;

  /// No description provided for @tutBooksBody.
  ///
  /// In en, this message translates to:
  /// **'Write long pieces as Books made of chapters. Read them in a clean, scrollable reader with themes, adjustable font size, bookmarks and highlights.'**
  String get tutBooksBody;

  /// No description provided for @tutJournalTitle.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get tutJournalTitle;

  /// No description provided for @tutJournalBody.
  ///
  /// In en, this message translates to:
  /// **'Keep a daily diary from the Journal tab. Entries stay tied to their day and never show up in Home or search.'**
  String get tutJournalBody;

  /// No description provided for @tutCryptTitle.
  ///
  /// In en, this message translates to:
  /// **'Crypt'**
  String get tutCryptTitle;

  /// No description provided for @tutCryptBody.
  ///
  /// In en, this message translates to:
  /// **'A folder that only opens with your fingerprint or screen lock, and its contents never appear in feeds or search.\n\nHeads up: Crypt locks the door, but items are stored unencrypted on this device and are readable in backups. Do not keep passwords or bank details in it.'**
  String get tutCryptBody;

  /// No description provided for @tutTipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Good to know'**
  String get tutTipsTitle;

  /// No description provided for @tutTipsBody.
  ///
  /// In en, this message translates to:
  /// **'Search finds notes, sparks and folders in one place. Pin up to 10 favourites per feed. Archive hides things without deleting, and deleted items wait 30 days in Recently deleted. Back up everything and switch to dark mode from Settings.'**
  String get tutTipsBody;

  /// No description provided for @guideTitle.
  ///
  /// In en, this message translates to:
  /// **'How Braim works'**
  String get guideTitle;

  /// No description provided for @guideSettingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get guideSettingsLabel;

  /// No description provided for @driveSection.
  ///
  /// In en, this message translates to:
  /// **'Google Drive'**
  String get driveSection;

  /// No description provided for @driveSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Drive backup not set up'**
  String get driveSetupTitle;

  /// No description provided for @driveSetupBody.
  ///
  /// In en, this message translates to:
  /// **'Add a Google OAuth client ID to enable automatic Google Drive backup. See docs/google_drive_setup.md in the project.'**
  String get driveSetupBody;

  /// No description provided for @driveConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect Google Drive'**
  String get driveConnect;

  /// No description provided for @driveConnectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to back up automatically to Drive'**
  String get driveConnectSubtitle;

  /// No description provided for @driveConnectedAs.
  ///
  /// In en, this message translates to:
  /// **'Connected as {email}'**
  String driveConnectedAs(String email);

  /// No description provided for @driveBackupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up to Drive now'**
  String get driveBackupNow;

  /// No description provided for @driveAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic backup'**
  String get driveAutoTitle;

  /// No description provided for @driveAutoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Back up to Drive when you leave the app'**
  String get driveAutoSubtitle;

  /// No description provided for @driveRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from Drive'**
  String get driveRestoreTitle;

  /// No description provided for @driveRestoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Replace everything with a Drive backup'**
  String get driveRestoreSubtitle;

  /// No description provided for @driveDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get driveDisconnect;

  /// No description provided for @drivePickTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a backup to restore'**
  String get drivePickTitle;

  /// No description provided for @driveNoBackups.
  ///
  /// In en, this message translates to:
  /// **'No backups on Drive yet'**
  String get driveNoBackups;

  /// No description provided for @driveConnected.
  ///
  /// In en, this message translates to:
  /// **'Google Drive connected'**
  String get driveConnected;

  /// No description provided for @driveConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect: {error}'**
  String driveConnectFailed(String error);

  /// No description provided for @driveBackingUp.
  ///
  /// In en, this message translates to:
  /// **'Backing up to Drive…'**
  String get driveBackingUp;

  /// No description provided for @driveBackedUp.
  ///
  /// In en, this message translates to:
  /// **'Backed up to Drive'**
  String get driveBackedUp;

  /// No description provided for @driveBackupFailed.
  ///
  /// In en, this message translates to:
  /// **'Drive backup failed: {error}'**
  String driveBackupFailed(String error);
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

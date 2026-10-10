import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';

import '../models/space.dart';
import '../services/shared_text.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

const _channel = MethodChannel('braim/share');

/// The tiny app run by ShareActivity's `shareMain` entrypoint: a Pinterest-style
/// popup over the sharing app that saves the shared link into a chosen folder.
class SharePopupApp extends StatefulWidget {
  const SharePopupApp({super.key});

  @override
  State<SharePopupApp> createState() => _SharePopupAppState();
}

class _SharePopupAppState extends State<SharePopupApp> {
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolveBrightness();
  }

  /// Resolve dark mode BEFORE the theme is built, so the popup's theme (and its
  /// ListTile ink) matches the phone — otherwise the theme baked a light scheme
  /// and folder names came out dark-on-dark in dark mode.
  Future<void> _resolveBrightness() async {
    try {
      final data = await StorageService.instance.load();
      AppPalette.dark = data.darkFollowSystem
          ? PlatformDispatcher.instance.platformBrightness == Brightness.dark
          : data.darkMode;
    } catch (_) {}
    if (mounted) setState(() => _resolved = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(AppPalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _resolved
          ? const SharePopupScreen()
          : const Scaffold(backgroundColor: Colors.transparent),
    );
  }
}

class SharePopupScreen extends StatefulWidget {
  const SharePopupScreen({super.key});

  @override
  State<SharePopupScreen> createState() => _SharePopupScreenState();
}

class _SharePopupScreenState extends State<SharePopupScreen> {
  SharedText? _shared;
  List<Space> _spaces = const [];
  bool _loading = true;
  String? _savedTo;
  bool _creatingFolder = false;
  final _folderCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  /// The chosen fold, or null for the default destination (Home for a note,
  /// Sparks for a link). While [_creatingFolder], the new fold is chosen.
  String? _spaceId;

  /// A link (with at most a short caption, like a shared headline) becomes a
  /// spark; anything else is filed as a note. See [SharedText].
  bool get _isNote => !(_shared?.isLink ?? false);

  bool get _hasContent =>
      _shared != null && (_shared!.isLink || _shared!.caption.isNotEmpty);

  /// A link can always be saved; a note needs a title or some text.
  bool get _canSave =>
      _hasContent &&
      (!_isNote ||
          _titleCtrl.text.trim().isNotEmpty ||
          _bodyCtrl.text.trim().isNotEmpty) &&
      (!_creatingFolder || _folderCtrl.text.trim().isNotEmpty);

  @override
  void dispose() {
    _folderCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? shared;
    try {
      shared = await _channel.invokeMethod<String>('getSharedText');
    } catch (_) {}
    final parsed = SharedText.parse(shared ?? '');
    final data = await StorageService.instance.load();
    AppPalette.dark = data.darkFollowSystem
        ? PlatformDispatcher.instance.platformBrightness == Brightness.dark
        : data.darkMode;
    if (!mounted) return;
    setState(() {
      _shared = parsed;
      // Shared words land where they belong: a link's headline as the
      // spark's title, shared text as the note's body. Both stay editable.
      if (parsed.isLink) {
        _titleCtrl.text = parsed.caption.replaceAll('\n', ' ');
      } else {
        _bodyCtrl.text = parsed.caption;
      }
      _spaces = data.spaces
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _loading = false;
    });
    if (!_hasContent) {
      // Nothing usable was shared; bow out quietly.
      Future.delayed(const Duration(milliseconds: 1200), _close);
    }
  }

  // Saves go through the share inbox (one file per share): this engine never
  // writes the main data file, so it can't race the main app's own saves.
  // The main app drains the inbox on next launch/resume and de-duplicates.

  Future<void> _save() async {
    if (!_canSave || _savedTo != null) return;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final String label;
    final Map<String, dynamic> dest;
    if (_creatingFolder) {
      label = _folderCtrl.text.trim();
      dest = {'newFolderName': label};
    } else {
      final space = _spaces.where((s) => s.id == _spaceId).firstOrNull;
      label =
          space?.name ?? (_isNote ? context.t.tabHome : context.t.tabCards);
      dest = {'spaceId': space?.id};
    }
    final record = <String, dynamic>{
      if (_isNote) 'noteText': body else 'url': _shared!.url,
      if (title.isNotEmpty) 'title': title,
      if (!_isNote && body.isNotEmpty) 'body': body,
      ...dest,
    };
    setState(() => _savedTo = label);
    await StorageService.instance.saveShareInbox(record);
    await Future.delayed(const Duration(milliseconds: 650));
    _close();
  }

  void _choose(String? spaceId) => setState(() {
        _creatingFolder = false;
        _spaceId = spaceId;
      });

  void _close() {
    _channel.invokeMethod('close').catchError((_) {
      SystemNavigator.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: Container(
          color: Colors.black.withValues(alpha: 0.30),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // absorb taps on the card
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                constraints: const BoxConstraints(maxHeight: 560),
                decoration: BoxDecoration(
                  color: AppPalette.sheet,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: _savedTo != null
                    ? _savedBody()
                    : (_loading ? _loadingBody() : _pickerBody()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadingBody() {
    return const SizedBox(
      height: 90,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }

  Widget _savedBody() {
    return SizedBox(
      height: 90,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF34A853), size: 34),
          const SizedBox(height: 8),
          Text(
            context.t.savedToName(_savedTo!),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppPalette.inkPrimary,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _field(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(color: AppPalette.inkSecondary),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Widget _pickerBody() {
    if (!_hasContent) {
      return SizedBox(
        height: 90,
        child: Center(
          child: Text(
            context.t.noLinkFound,
            style: TextStyle(color: AppPalette.inkSecondary),
          ),
        ),
      );
    }

    // One scrolling column, so the fields and the folds still fit while the
    // keyboard is up.
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            ClipOval(
              child: Image.asset('assets/logo.png',
                  width: 30, height: 30, fit: BoxFit.cover, cacheWidth: 90),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isNote ? context.t.saveNoteToBraim : context.t.saveToBraim,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.inkPrimary,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 20, color: AppPalette.inkSecondary),
              onPressed: _close,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: context.t.shareSave,
              icon: const Icon(Icons.check_rounded, size: 20),
              onPressed: _canSave ? _save : null,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (!_isNote) ...[
          const SizedBox(height: 2),
          Text(
            _shared!.url!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: AppPalette.inkSecondary),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _titleCtrl,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppPalette.inkPrimary,
          ),
          decoration: _field(context.t.shareTitleHint),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bodyCtrl,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontSize: 14.5, color: AppPalette.inkPrimary),
          decoration: _field(context.t.shareBodyHint),
        ),
        const SizedBox(height: 10),
        // The default destination leads: Home for notes, Sparks for links.
        _option(
          icon: _isNote ? Icons.sticky_note_2_outlined : Icons.style_rounded,
          label: _isNote ? context.t.tabHome : context.t.tabCards,
          sub: context.t.noFolder,
          selected: !_creatingFolder && _spaceId == null,
          onTap: () => _choose(null),
        ),
        if (_creatingFolder)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: TextField(
              controller: _folderCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              style: TextStyle(fontSize: 14.5, color: AppPalette.inkPrimary),
              decoration: _field(context.t.folderName),
            ),
          )
        else
          _option(
            icon: Icons.create_new_folder_outlined,
            label: context.t.newFolder,
            onTap: () => setState(() => _creatingFolder = true),
          ),
        for (final s in _spaces)
          _option(
            icon: Icons.folder_rounded,
            label: s.name,
            selected: !_creatingFolder && _spaceId == s.id,
            onTap: () => _choose(s.id),
          ),
      ],
    );
  }

  Widget _option({
    required IconData icon,
    required String label,
    String? sub,
    bool selected = false,
    required VoidCallback onTap,
  }) {
    final accent = AppPalette.scheme.primary;
    return Material(
      color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(11),
                ),
                child:
                    Icon(icon, size: 19, color: AppPalette.inkSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.inkPrimary,
                  ),
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  style: TextStyle(
                      fontSize: 12, color: AppPalette.inkSecondary),
                ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, size: 18, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

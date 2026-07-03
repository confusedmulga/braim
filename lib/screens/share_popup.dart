import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/space.dart';
import '../models/tweet_card.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

const _channel = MethodChannel('braim/share');

/// The tiny app run by ShareActivity's `shareMain` entrypoint: a Pinterest-style
/// popup over the sharing app that saves the shared link into a chosen folder.
class SharePopupApp extends StatelessWidget {
  const SharePopupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SharePopupScreen(),
    );
  }
}

class SharePopupScreen extends StatefulWidget {
  const SharePopupScreen({super.key});

  @override
  State<SharePopupScreen> createState() => _SharePopupScreenState();
}

class _SharePopupScreenState extends State<SharePopupScreen> {
  String? _url;
  List<Space> _spaces = const [];
  bool _loading = true;
  String? _savedTo;
  bool _creatingFolder = false;
  final _folderCtrl = TextEditingController();

  @override
  void dispose() {
    _folderCtrl.dispose();
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
    final match = RegExp(r'https?://\S+').firstMatch(shared ?? '');
    final data = await StorageService.instance.load();
    if (!mounted) return;
    setState(() {
      _url = match?.group(0);
      _spaces = data.spaces
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _loading = false;
    });
    if (_url == null) {
      // Nothing usable was shared; bow out quietly.
      Future.delayed(const Duration(milliseconds: 1200), _close);
    }
  }

  Future<void> _saveTo(String? spaceId, String label) async {
    if (_url == null || _savedTo != null) return;
    setState(() => _savedTo = label);
    final data = await StorageService.instance.load();
    data.cards.add(TweetCard(url: _url!, spaceId: spaceId));
    await StorageService.instance.save(data);
    await Future.delayed(const Duration(milliseconds: 650));
    _close();
  }

  /// Creates a new folder and files the link straight into it.
  Future<void> _createFolderAndSave() async {
    final name = _folderCtrl.text.trim();
    if (name.isEmpty || _url == null || _savedTo != null) return;
    setState(() => _savedTo = name);
    final data = await StorageService.instance.load();
    final space = Space(name: name);
    data.spaces.add(space);
    data.cards.add(TweetCard(url: _url!, spaceId: space.id));
    await StorageService.instance.save(data);
    await Future.delayed(const Duration(milliseconds: 650));
    _close();
  }

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
                constraints: const BoxConstraints(maxHeight: 420),
                decoration: BoxDecoration(
                  color: Colors.white,
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
            'Saved to $_savedTo',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppPalette.inkPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerBody() {
    if (_url == null) {
      return const SizedBox(
        height: 90,
        child: Center(
          child: Text(
            'No link found in the shared text',
            style: TextStyle(color: AppPalette.inkSecondary),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipOval(
              child: Image.asset('assets/logo.png',
                  width: 30, height: 30, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            const Text(
              'Save to Braim',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: AppPalette.inkPrimary,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 20, color: AppPalette.inkSecondary),
              onPressed: _close,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _url!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(fontSize: 12.5, color: AppPalette.inkSecondary),
        ),
        const SizedBox(height: 10),
        if (_creatingFolder)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _folderCtrl,
                    autofocus: true,
                    onSubmitted: (_) => _createFolderAndSave(),
                    style: const TextStyle(
                        fontSize: 14.5, color: AppPalette.inkPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Folder name',
                      hintStyle:
                          const TextStyle(color: AppPalette.inkSecondary),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _createFolderAndSave,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              if (!_creatingFolder)
                _option(
                  icon: Icons.create_new_folder_outlined,
                  label: 'New folder',
                  sub: 'Create & save',
                  onTap: () => setState(() => _creatingFolder = true),
                ),
              _option(
                icon: Icons.style_rounded,
                label: 'Cards',
                sub: 'No folder',
                onTap: () => _saveTo(null, 'Cards'),
              ),
              for (final s in _spaces)
                _option(
                  icon: Icons.folder_rounded,
                  label: s.name,
                  onTap: () => _saveTo(s.id, s.name),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _option({
    required IconData icon,
    required String label,
    String? sub,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.inkPrimary,
                  ),
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  style: const TextStyle(
                      fontSize: 12, color: AppPalette.inkSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

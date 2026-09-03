import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Your Google **Web application** OAuth client ID
/// (e.g. `1234-abc.apps.googleusercontent.com`), used to authenticate the
/// Google account. Leave empty to keep Drive backup switched off — the app
/// still builds and runs, the Drive section just shows "setup required".
///
/// Paste it into [defaultValue] below, or pass it at build/run time with
/// `--dart-define=BRAIM_GDRIVE_CLIENT_ID=...`. See docs/google_drive_setup.md.
const String kGoogleServerClientId = String.fromEnvironment(
  'BRAIM_GDRIVE_CLIENT_ID',
  // Braim Web OAuth client (Google Cloud project "braim-77"). A client ID is
  // public by design (safe to commit); the client secret is never used here.
  defaultValue:
      '354565440160-357hj1be88ljhg2kj7tidvd9mqp1vkvd.apps.googleusercontent.com',
);

/// One backup file living in the app's private Drive folder.
class DriveBackupFile {
  DriveBackupFile({
    required this.id,
    required this.name,
    this.sizeBytes,
    this.modifiedTime,
  });

  final String id;
  final String name;
  final int? sizeBytes;
  final DateTime? modifiedTime;

  factory DriveBackupFile.fromJson(Map<String, dynamic> j) => DriveBackupFile(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'backup.zip',
        sizeBytes: int.tryParse('${j['size'] ?? ''}'),
        modifiedTime:
            DateTime.tryParse('${j['modifiedTime'] ?? j['createdTime'] ?? ''}'),
      );
}

/// Signs in with Google and reads/writes backup zips in Drive's hidden
/// `appDataFolder` — an app-private space that never clutters the user's Drive
/// and only ever holds this app's files (the `drive.appdata` scope).
///
/// Uses the Drive v3 REST API directly over `http` with the access token from
/// google_sign_in 7.x, so there's no dependency on `googleapis` or a sign-in
/// bridge that lags the plugin's major versions.
class DriveBackupService {
  DriveBackupService._();
  static final DriveBackupService instance = DriveBackupService._();

  /// App-private Drive folder; invisible in the user's Drive UI.
  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _appFolder = 'appDataFolder';
  static const _apiFiles = 'https://www.googleapis.com/drive/v3/files';
  static const _apiUpload =
      'https://www.googleapis.com/upload/drive/v3/files';

  bool _inited = false;

  /// Whether a Web client ID has been provided; without one the feature is off.
  bool get isConfigured => kGoogleServerClientId.isNotEmpty;

  Future<void> _ensureInit() async {
    if (_inited) return;
    await GoogleSignIn.instance.initialize(
      serverClientId:
          kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
    );
    _inited = true;
  }

  /// Interactive connect. Returns the account email, or null if the user
  /// cancelled the picker / consent.
  Future<String?> connect() async {
    await _ensureInit();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('Google sign-in is not available on this device.');
    }
    try {
      final account =
          await GoogleSignIn.instance.authenticate(scopeHint: const [_scope]);
      // Grab the Drive grant now (prompting once) so later backups are silent.
      final headers = await account.authorizationClient
          .authorizationHeaders(const [_scope], promptIfNecessary: true);
      if (headers == null) return null; // scope not granted
      return account.email;
    } on GoogleSignInException catch (e) {
      // A cancelled picker/consent is a quiet no-op, not an error.
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _ensureInit();
    await GoogleSignIn.instance.disconnect();
  }

  /// Silent auth headers (no UI), or null when not connected or the grant is no
  /// longer available — callers must handle null rather than prompting.
  Future<Map<String, String>?> _silentHeaders() async {
    await _ensureInit();
    final account =
        await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return null;
    return account.authorizationClient.authorizationHeaders(const [_scope]);
  }

  Future<Map<String, String>> _requireHeaders() async {
    final headers = await _silentHeaders();
    if (headers == null) {
      throw StateError('Not connected to Google Drive.');
    }
    return headers;
  }

  /// Uploads [zip] into the app folder as a single multipart/related request
  /// (metadata + bytes), so the file appears atomically.
  Future<void> uploadBackup(File zip, {required String filename}) async {
    final headers = await _requireHeaders();
    final bytes = await zip.readAsBytes();
    final boundary = 'braim${DateTime.now().microsecondsSinceEpoch}';
    final meta = jsonEncode({
      'name': filename,
      'parents': [_appFolder],
    });
    final body = <int>[
      ...utf8.encode('--$boundary\r\n'),
      ...utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
      ...utf8.encode(meta),
      ...utf8.encode('\r\n--$boundary\r\n'),
      ...utf8.encode('Content-Type: application/zip\r\n\r\n'),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final resp = await http.post(
      Uri.parse('$_apiUpload?uploadType=multipart&fields=id,name,modifiedTime'),
      headers: {
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('Drive upload failed (${resp.statusCode}).');
    }
  }

  /// Backups in the app folder, newest first.
  Future<List<DriveBackupFile>> listBackups() async {
    final headers = await _requireHeaders();
    final uri = Uri.parse(_apiFiles).replace(queryParameters: {
      'spaces': _appFolder,
      'fields': 'files(id,name,size,modifiedTime,createdTime)',
      'orderBy': 'modifiedTime desc',
      'pageSize': '100',
    });
    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw StateError('Drive list failed (${resp.statusCode}).');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((map['files'] as List?) ?? const [])
        .map((e) => DriveBackupFile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Uint8List> downloadBackup(String fileId) async {
    final headers = await _requireHeaders();
    final resp = await http.get(
      Uri.parse('$_apiFiles/$fileId?alt=media'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw StateError('Drive download failed (${resp.statusCode}).');
    }
    return resp.bodyBytes;
  }

  Future<void> deleteBackup(String fileId) async {
    final headers = await _requireHeaders();
    final resp =
        await http.delete(Uri.parse('$_apiFiles/$fileId'), headers: headers);
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw StateError('Drive delete failed (${resp.statusCode}).');
    }
  }

  /// Keeps only the newest [keep] backups; older ones are removed. Best effort.
  Future<void> pruneOldBackups({int keep = 5}) async {
    final files = await listBackups();
    for (final f in files.skip(keep)) {
      try {
        await deleteBackup(f.id);
      } catch (_) {
        // A failed prune isn't worth surfacing; retried next backup.
      }
    }
  }
}

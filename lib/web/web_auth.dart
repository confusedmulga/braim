// Braim Web pairing and sessions: the 6-digit code shown in Settings, and the
// linked browsers kept in braim_web_sessions.json. That file is Braim Web's
// own state: it is not part of Braim's backups. See docs/braim-web-plan.md,
// sections 5.3 and 5.4.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import 'web_security.dart';

/// What one pairing attempt came to.
enum PairOutcome {
  /// The code matched; the browser gets a session.
  paired,

  /// The code didn't match the current one.
  wrong,

  /// The code matched the one that just expired.
  expired,

  /// Too many misses; pairing is refused for a while.
  locked,
}

/// The rotating 6-digit pairing code. A code lives for [codeLife] and is
/// replaced after one successful use. After [maxMisses] wrong attempts against
/// the current code, the code is replaced and every attempt is refused for
/// [lockout].
class WebPairing {
  WebPairing({DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure() {
    _issue();
  }

  static const codeLife = Duration(minutes: 2);
  static const maxMisses = 5;
  static const lockout = Duration(seconds: 30);

  /// Six ASCII digits.
  static final RegExp codePattern = RegExp(r'^[0-9]{6}$');

  final DateTime Function() _now;
  final Random _random;

  String _code = '';
  late DateTime _issuedAt;
  String? _expired;
  int _misses = 0;
  DateTime? _lockedUntil;

  /// The code to show now. Expired codes are replaced on read.
  String get code {
    _refresh();
    return _code;
  }

  /// Time until [code] is replaced.
  Duration get timeLeft {
    _refresh();
    final left = codeLife - _now().difference(_issuedAt);
    return left.isNegative ? Duration.zero : left;
  }

  /// Time until pairing is accepted again, or zero when not locked.
  Duration get lockLeft {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Replaces the code now.
  void rotate() {
    _expired = null;
    _issue();
  }

  /// Checks one attempt. [input] must already be six digits.
  PairOutcome check(String input) {
    _refresh();
    if (lockLeft > Duration.zero) return PairOutcome.locked;
    if (constantTimeEquals(input, _code)) {
      rotate(); // single use
      return PairOutcome.paired;
    }
    _misses++;
    if (_misses >= maxMisses) {
      rotate();
      _lockedUntil = _now().add(lockout);
      return PairOutcome.locked;
    }
    final expired = _expired;
    return expired != null && constantTimeEquals(input, expired)
        ? PairOutcome.expired
        : PairOutcome.wrong;
  }

  void _refresh() {
    if (_now().difference(_issuedAt) < codeLife) return;
    final old = _code;
    _issue();
    _expired = old;
  }

  void _issue() {
    String next;
    do {
      next = _random.nextInt(1000000).toString().padLeft(6, '0');
    } while (next == _code);
    _code = next;
    _issuedAt = _now();
    _misses = 0;
  }
}

/// One linked browser. Only the hash of its token is kept.
class WebSession {
  WebSession({
    required this.id,
    required this.hash,
    required this.label,
    required this.created,
    required this.lastSeen,
  });

  /// A random public id: used to log the browser out and to name its edit
  /// leases. Not the token, and not derived from it.
  final String id;

  /// base64url(sha256(token)).
  final String hash;

  /// "Chrome on Windows", built from the user agent when the browser paired.
  final String label;

  final DateTime created;
  DateTime lastSeen;

  Map<String, dynamic> toJson() => {
    'id': id,
    'hash': hash,
    'label': label,
    'created': created.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
  };

  static WebSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final hash = json['hash'];
    final label = json['label'];
    final created = DateTime.tryParse('${json['created']}');
    final lastSeen = DateTime.tryParse('${json['lastSeen']}');
    if (id is! String ||
        hash is! String ||
        label is! String ||
        created == null ||
        lastSeen == null) {
      return null;
    }
    return WebSession(
      id: id,
      hash: hash,
      label: label,
      created: created,
      lastSeen: lastSeen,
    );
  }
}

/// The linked browsers, persisted in [file]. At most [maxSessions]; a session
/// unused for [idleLimit] is dropped.
class WebSessionStore {
  WebSessionStore(this.file, {DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();

  /// The store in the app's documents folder, next to (but never inside) the
  /// library and its backups.
  static Future<WebSessionStore> inDocuments() async {
    final dir = await getApplicationDocumentsDirectory();
    return WebSessionStore(File('${dir.path}/$fileName'));
  }

  static const fileName = 'braim_web_sessions.json';
  static const maxSessions = 5;
  static const idleLimit = Duration(days: 30);

  /// How long a last-seen update may wait before it is written.
  static const touchWriteDelay = Duration(minutes: 1);

  /// A token as issued: 32 random bytes, base64url without padding.
  static final RegExp tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  final File file;
  final DateTime Function() _now;
  final Random _random;

  final Map<String, WebSession> _byHash = {};
  bool _loaded = false;
  Timer? _touchTimer;
  Future<void> _writeChain = Future.value();

  /// sha256 of [token], base64url without padding.
  static String hashToken(String token) => base64Url
      .encode(sha256.convert(utf8.encode(token)).bytes)
      .replaceAll('=', '');

  /// Reads the file. A missing or unreadable file means no linked browsers,
  /// so every browser pairs again; nothing else is lost.
  Future<void> load() async {
    _byHash.clear();
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final list = json is Map ? json['sessions'] : null;
        if (list is List) {
          for (final raw in list) {
            final s = WebSession.fromJson(raw);
            if (s != null) _byHash[s.hash] = s;
          }
        }
      }
    } catch (_) {
      _byHash.clear();
    }
    _loaded = true;
    if (_prune()) await _save();
  }

  /// Linked browsers, most recently seen first.
  List<WebSession> get sessions {
    if (_prune()) unawaited(_save());
    return _byHash.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  /// Whether no more browsers may pair.
  bool get isFull {
    if (_prune()) unawaited(_save());
    return _byHash.length >= maxSessions;
  }

  /// Links a new browser and returns its token, which goes into the cookie and
  /// is never stored.
  Future<({String token, WebSession session})> create({
    required String label,
  }) async {
    assert(_loaded, 'load() first');
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    final idBytes = List<int>.generate(12, (_) => _random.nextInt(256));
    final now = _now();
    final session = WebSession(
      id: base64Url.encode(idBytes),
      hash: hashToken(token),
      label: label,
      created: now,
      lastSeen: now,
    );
    _byHash[session.hash] = session;
    await _save();
    return (token: token, session: session);
  }

  /// The session for [token], or null when the token is malformed, unknown or
  /// idle for too long (an idle one is dropped).
  WebSession? lookup(String? token) {
    if (token == null || !tokenPattern.hasMatch(token)) return null;
    final hash = hashToken(token);
    final session = _byHash[hash];
    if (session == null) return null;
    if (_idle(session)) {
      _byHash.remove(hash);
      unawaited(_save());
      return null;
    }
    return session;
  }

  /// Marks [session] as used now. The write is batched.
  void touch(WebSession session) {
    session.lastSeen = _now();
    _touchTimer ??= Timer(touchWriteDelay, () {
      _touchTimer = null;
      unawaited(_save());
    });
  }

  /// Logs one browser out.
  Future<bool> remove(String id) async {
    final before = _byHash.length;
    _byHash.removeWhere((_, s) => s.id == id);
    if (_byHash.length == before) return false;
    await _save();
    return true;
  }

  /// Logs every browser out.
  Future<void> removeAll() async {
    _byHash.clear();
    await _save();
  }

  /// Writes any batched last-seen update now.
  Future<void> flush() async {
    if (_touchTimer != null) {
      _touchTimer!.cancel();
      _touchTimer = null;
      await _save();
    }
    await _writeChain;
  }

  bool _idle(WebSession s) => _now().difference(s.lastSeen) >= idleLimit;

  bool _prune() {
    final before = _byHash.length;
    _byHash.removeWhere((_, s) => _idle(s));
    return _byHash.length != before;
  }

  /// Atomic write: a temp file renamed into place, one write at a time.
  Future<void> _save() {
    final json = jsonEncode({
      'version': 1,
      'sessions': [for (final s in _byHash.values) s.toJson()],
    });
    return _writeChain = _writeChain
        .then((_) async {
          final tmp = File('${file.path}.tmp');
          await tmp.writeAsString(json, flush: true);
          await tmp.rename(file.path);
        })
        .catchError((_) {});
  }
}

/// A short label for a browser from its user agent, such as "Chrome on
/// Windows". Built only from fixed names, never from the user agent's text.
String webSessionLabel(String? userAgent, AppLocalizations l10n) {
  final ua = userAgent ?? '';
  final String? browser;
  if (ua.contains('Edg/') || ua.contains('EdgA/') || ua.contains('EdgiOS/')) {
    browser = 'Edge';
  } else if (ua.contains('OPR/') || ua.contains('Opera')) {
    browser = 'Opera';
  } else if (ua.contains('SamsungBrowser/')) {
    browser = 'Samsung Internet';
  } else if (ua.contains('Firefox/') || ua.contains('FxiOS/')) {
    browser = 'Firefox';
  } else if (ua.contains('Chrome/') || ua.contains('CriOS/')) {
    browser = 'Chrome';
  } else if (ua.contains('Safari/')) {
    browser = 'Safari';
  } else {
    browser = null;
  }
  final String? os;
  if (ua.contains('Windows')) {
    os = 'Windows';
  } else if (ua.contains('CrOS')) {
    os = 'ChromeOS';
  } else if (ua.contains('Android')) {
    os = 'Android';
  } else if (ua.contains('iPhone') || ua.contains('iPad')) {
    os = 'iOS';
  } else if (ua.contains('Macintosh') || ua.contains('Mac OS X')) {
    os = 'macOS';
  } else if (ua.contains('Linux')) {
    os = 'Linux';
  } else {
    os = null;
  }
  final name = browser ?? l10n.webUnknownBrowser;
  return os == null ? name : l10n.webBrowserOn(name, os);
}

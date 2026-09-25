/// The contract between the phone server and a browser in remote mode.
///
/// HTTP for one-shot calls; one WebSocket (`/api/live`) per open tab for the
/// library itself. Every frame is a JSON object with an `op`:
///
/// browser -> phone
///   {op: auth, token}             first frame; the phone closes on a bad one
///   {op: push, seq, delta}        rows/settings changed in the browser
///   {op: addTyping, ms}           typing time the browser added
///   {op: ping, active}            keep-alive; active = the user did something
///
/// phone -> browser
///   {op: snapshot, delta, crypt}  the whole library, right after auth
///   {op: push, delta}             rows/settings changed elsewhere
///   {op: ack, seq}                a push has landed in the phone's library
///   {op: lock, ids}               the Crypt re-locked: drop these ids
///   {op: bye, reason}             the session was revoked or the server stopped
///   {op: pong}
library;

const kPhoneServerPort = 8787;
const kRemoteProto = 1;

class RemoteApi {
  RemoteApi._();

  static const hello = '/api/hello';
  static const pair = '/api/pair';
  static const session = '/api/session';
  static const live = '/api/live';
  static const imagePrefix = '/api/image/';
  static const search = '/api/search';
  static const fetch = '/api/fetch';
  static const cryptUnlock = '/api/crypt/unlock';
  static const cryptLock = '/api/crypt/lock';
  static const snapshot = '/api/snapshot';
}

/// A stored image's file name as it may travel in a URL: no path separators,
/// not hidden, a sane length.
bool isSafeImageKey(String key) =>
    key.isNotEmpty &&
    key.length <= 120 &&
    !key.startsWith('.') &&
    RegExp(r'^[A-Za-z0-9._\-]+$').hasMatch(key);

/// Largest page body the phone fetches on a browser's behalf.
const kMaxFetchBytes = 3 * 1024 * 1024;

/// Largest image a browser may upload.
const kMaxImageUploadBytes = 25 * 1024 * 1024;

/// How long an unlocked Crypt stays open in a browser without activity.
const kCryptIdleLock = Duration(minutes: 10);

/// How long a pairing code stays valid.
const kPairingCodeLifetime = Duration(minutes: 5);

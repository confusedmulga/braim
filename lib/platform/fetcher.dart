import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Outbound page fetches for link previews and YouTube data. The phone fetches
/// directly; a browser can't read other sites (CORS), so remote mode swaps in
/// a fetcher that asks the phone to do it.
abstract class Fetcher {
  Future<http.Response> get(Uri url, {Map<String, String>? headers});

  static Fetcher instance = DirectFetcher();
}

class DirectFetcher implements Fetcher {
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      http.get(url, headers: headers);
}

/// Runs [work] on a background isolate where there is one; in a browser
/// (single-threaded) it runs inline.
Future<T> runOffThread<T>(FutureOr<T> Function() work) async =>
    kIsWeb ? await work() : await Isolate.run(work);

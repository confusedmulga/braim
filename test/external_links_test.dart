import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:braim/services/external_links.dart';

class _FakeLauncher extends UrlLauncherPlatform {
  _FakeLauncher({this.canOpen = true});
  final bool canOpen;
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => canOpen;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return canOpen;
  }
}

void main() {
  group('withUrlScheme', () {
    test('gives a bare address https', () {
      expect(withUrlScheme('example.com'), 'https://example.com');
      expect(withUrlScheme('  x.com/jack/status/20 '),
          'https://x.com/jack/status/20');
    });

    test('keeps an address that already has a scheme', () {
      expect(withUrlScheme('http://a.com'), 'http://a.com');
      expect(withUrlScheme('HTTPS://A.com/x'), 'HTTPS://A.com/x');
      expect(withUrlScheme('mailto:me@a.com'), 'mailto:me@a.com');
      expect(withUrlScheme('tel:+15551234'), 'tel:+15551234');
    });

    test('empty stays empty', () {
      expect(withUrlScheme('   '), '');
    });
  });

  group('openExternalUrl', () {
    test('opens a bare address as https and reports success', () async {
      final launcher = _FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      expect(await openExternalUrl('example.com/page'), isTrue);
      expect(launcher.launched, ['https://example.com/page']);
    });

    test('reports failure when nothing can open it (no throw)', () async {
      UrlLauncherPlatform.instance = _FakeLauncher(canOpen: false);
      expect(await openExternalUrl('https://example.com'), isFalse);
      expect(await openExternalUrl(''), isFalse);
    });
  });

  test('backups stay out of the Google backup wherever they are written', () {
    // External storage, and the documents-dir fallback when there is none.
    for (final f in [
      'android/app/src/main/res/xml/data_extraction_rules.xml',
      'android/app/src/main/res/xml/backup_rules.xml',
    ]) {
      final xml = File(f).readAsStringSync();
      expect(xml, contains('domain="external" path="Backups"'), reason: f);
      expect(xml, contains('domain="root" path="app_flutter/Backups"'),
          reason: f);
    }
  });
}

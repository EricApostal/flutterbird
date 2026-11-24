import 'dart:convert';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

void main() {
  group('Manifest.parse', () {
    test('reads a Manifest V2 extension', () {
      final result = Manifest.parse('''
{
  // Firefox allows comments in manifests.
  "manifest_version": 2,
  "name": "Example",
  "version": "1.2.3",
  "description": "Does things",
  "default_locale": "en",
  "browser_specific_settings": {"gecko": {"id": "example@test", "strict_min_version": "115.0"}},
  "icons": {"16": "/icons/16.png", "48": "icons/48.png", "128": "./icons/128.png"},
  "permissions": ["tabs", "storage", "webRequest", "webRequestBlocking", "*://*.example.com/*", "<all_urls>"],
  "optional_permissions": ["bookmarks", "https://opt.example.org/*"],
  "background": {"scripts": ["bg.js"], "persistent": false},
  "browser_action": {"default_title": "Go", "default_popup": "popup.html", "default_icon": "icon.png"},
  "page_action": {"default_title": "Page"},
  "options_ui": {"page": "options.html", "open_in_tab": true},
  "content_scripts": [{
    "matches": ["https://*.example.com/*", "bogus"],
    "js": ["a.js", "../evil.js"],
    "css": ["a.css"],
    "run_at": "document_start",
    "all_frames": true
  }],
  "web_accessible_resources": ["img/*.png"],
  "commands": {"toggle": {"suggested_key": {"default": "Ctrl+Shift+Y"}, "description": "Toggle"}},
  "omnibox": {"keyword": "ex"}
}
''');
      final m = result.manifest;

      expect(m.manifestVersion, 2);
      expect(m.type, ExtensionType.extension);
      expect(m.id, 'example@test');
      expect(m.gecko!.strictMinVersion, '115.0');
      expect(m.icons['16'], 'icons/16.png');
      expect(m.icons['128'], 'icons/128.png');

      expect(m.permissions, [
        'tabs',
        'storage',
        'webRequest',
        'webRequestBlocking',
      ]);
      expect(m.hostPermissions, ['*://*.example.com/*', '<all_urls>']);
      expect(m.optionalPermissions, ['bookmarks']);
      expect(m.optionalHostPermissions, ['https://opt.example.org/*']);

      expect(m.background!.scripts, ['bg.js']);
      expect(m.background!.persistent, isFalse);

      expect(m.action!.kind, ActionKind.browserAction);
      expect(m.action!.defaultPopup, 'popup.html');
      expect(m.action!.defaultIcon, {'any': 'icon.png'});
      expect(m.pageAction!.kind, ActionKind.pageAction);
      expect(m.options!.openInTab, isTrue);

      final script = m.contentScripts.single;
      expect(script.matches, ['https://*.example.com/*']);
      expect(script.js, ['a.js']);
      expect(script.css, ['a.css']);
      expect(script.runAt, RunAt.documentStart);
      expect(script.allFrames, isTrue);
      expect(script.world, ContentScriptWorld.isolated);

      expect(m.webAccessibleResources.single.resources, ['img/*.png']);
      expect(m.webAccessibleResources.single.matches, ['<all_urls>']);
      expect(m.commands.single.suggestedKey['default'], 'Ctrl+Shift+Y');
      expect(m.omniboxKeyword, 'ex');
      expect(
        m.contentSecurityPolicy.extensionPages,
        ContentSecurityPolicy.defaultMv2,
      );

      expect(result.warnings, contains(contains('"bogus"')));
      expect(result.warnings, contains(contains('../evil.js')));
    });

    test('reads a Manifest V3 extension', () {
      final m = Manifest.parse('''
{
  "manifest_version": 3,
  "name": "MV3",
  "version": "2.0",
  "applications": {"gecko": {"id": "mv3@test"}},
  "permissions": ["scripting", "declarativeNetRequest"],
  "host_permissions": ["https://*/*"],
  "background": {"service_worker": "sw.js", "scripts": ["bg.js"], "type": "module", "persistent": true},
  "action": {"default_popup": "/popup.html"},
  "content_security_policy": {"extension_pages": "script-src 'self'"},
  "web_accessible_resources": [{"resources": ["a.png"], "matches": ["https://x.com/*"]}],
  "declarative_net_request": {"rule_resources": [{"id": "r1", "enabled": true, "path": "rules.json"}]},
  "content_scripts": [{"matches": ["<all_urls>"], "js": ["m.js"], "world": "MAIN"}]
}
''').manifest;

      expect(m.isManifestV3, isTrue);
      expect(m.id, 'mv3@test', reason: '"applications" is the old key name');
      expect(m.permissions, ['scripting', 'declarativeNetRequest']);
      expect(m.hostPermissions, ['https://*/*']);
      expect(m.action!.kind, ActionKind.action);
      expect(m.action!.defaultPopup, 'popup.html');
      expect(m.background!.scripts, ['bg.js']);
      expect(m.background!.serviceWorker, 'sw.js');
      expect(
        m.background!.persistent,
        isFalse,
        reason: 'MV3 backgrounds are never persistent',
      );
      expect(m.background!.isModule, isTrue);
      expect(m.contentSecurityPolicy.extensionPages, "script-src 'self'");
      expect(m.webAccessibleResources.single.matches, ['https://x.com/*']);
      expect(m.dnrRuleResources.single.path, 'rules.json');
      expect(m.contentScripts.single.world, ContentScriptWorld.main);
    });

    test('defaults a V2 background to persistent', () {
      final m = Manifest.parse(
        '{"manifest_version":2,"name":"x","version":"1","background":{"scripts":["a.js"]}}',
      ).manifest;
      expect(m.background!.persistent, isTrue);
    });

    test('recognizes themes', () {
      final m = Manifest.parse(
        '{"manifest_version":2,"name":"T","version":"1","theme":{"colors":{}}}',
      ).manifest;
      expect(m.type, ExtensionType.theme);
    });

    test('keeps unknown permissions but warns', () {
      final result = Manifest.parse(
        '{"manifest_version":2,"name":"x","version":"1","permissions":["storage","telepathy"]}',
      );
      expect(result.manifest.permissions, ['storage', 'telepathy']);
      expect(result.warnings, contains(contains('telepathy')));
    });

    test('skips a content script with no usable matches', () {
      final result = Manifest.parse(
        '{"manifest_version":2,"name":"x","version":"1","content_scripts":[{"matches":["nope"],"js":["a.js"]}]}',
      );
      expect(result.manifest.contentScripts, isEmpty);
      expect(result.warnings, isNotEmpty);
    });

    test('ignores a UTF-8 byte-order mark', () {
      final bytes = [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('{"manifest_version":2,"name":"x","version":"1"}'),
      ];
      expect(Manifest.parseBytes(bytes).manifest.name, 'x');
    });

    test('does not mistake // inside a string for a comment', () {
      final m = Manifest.parse(
        '{"manifest_version":2,"name":"x","version":"1","homepage_url":"https://example.com/a//b"}',
      ).manifest;
      expect(m.homepageUrl, 'https://example.com/a//b');
    });

    test('rejects manifests that cannot be used', () {
      for (final source in [
        'not json',
        '[]',
        '{"manifest_version":1,"name":"x","version":"1"}',
        '{"manifest_version":"2","name":"x","version":"1"}',
        '{"manifest_version":2,"version":"1"}',
        '{"manifest_version":2,"name":"  ","version":"1"}',
        '{"manifest_version":2,"name":"x"}',
        '{"manifest_version":2,"name":"x","version":"has space"}',
      ]) {
        expect(
          () => Manifest.parse(source),
          throwsA(isA<ManifestException>()),
          reason: source,
        );
      }
    });
  });

  group('bestIconPath', () {
    test('picks the smallest icon that is big enough, else the largest', () {
      const icons = {'16': 'a', '48': 'b', '128': 'c'};
      expect(bestIconPath(icons, 32), 'b');
      expect(bestIconPath(icons, 48), 'b');
      expect(bestIconPath(icons, 200), 'c');
      expect(bestIconPath(icons, 1), 'a');
      expect(bestIconPath(const {'any': 'x'}, 48), 'x');
      expect(bestIconPath(const {}, 48), isNull);
    });
  });

  group('normalizeResourcePath', () {
    test('strips leading slashes and rejects escapes', () {
      expect(normalizeResourcePath('/a/b.js'), 'a/b.js');
      expect(normalizeResourcePath('./a.js'), 'a.js');
      expect(normalizeResourcePath('../a.js'), isNull);
      expect(normalizeResourcePath(''), isNull);
    });
  });
}

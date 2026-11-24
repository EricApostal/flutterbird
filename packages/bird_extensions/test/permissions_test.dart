import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

void main() {
  group('describePermissions', () {
    test('says "all websites" for any all-sites pattern', () {
      for (final pattern in ['<all_urls>', '*://*/*', 'https://*/*']) {
        final prompt = describePermissions(
          permissions: const [],
          hostPatterns: [pattern, 'https://a.com/*'],
        );
        expect(prompt.hostLines, ['Access your data for all websites']);
        expect(prompt.hasAllSitesAccess, isTrue);
      }
    });

    test('names domains and sites, and summarizes the overflow', () {
      final prompt = describePermissions(
        permissions: const [],
        hostPatterns: [
          for (var i = 0; i < 6; i++) 'https://*.d$i.com/*',
          'https://one.org/*',
        ],
      );
      expect(prompt.hostLines.take(4), [
        'Access your data for sites in the d0.com domain',
        'Access your data for sites in the d1.com domain',
        'Access your data for sites in the d2.com domain',
        'Access your data for sites in the d3.com domain',
      ]);
      expect(prompt.hostLines[4], 'Access your data in 2 other domains');
      expect(prompt.hostLines[5], 'Access your data for one.org');
      expect(prompt.hasAllSitesAccess, isFalse);
    });

    test('lists only the API permissions that warn, once each', () {
      final prompt = describePermissions(
        permissions: const [
          'storage',
          'alarms',
          'tabs',
          'history',
          'topSites',
          'bookmarks',
        ],
        hostPatterns: const [],
      );
      expect(prompt.apiLines, [
        'Access browser tabs',
        'Access browsing history',
        'Read and modify bookmarks',
      ]);
      expect(prompt.isEmpty, isFalse);
    });

    test('is empty when nothing warrants a warning', () {
      final prompt = describePermissions(
        permissions: const ['storage', 'alarms', 'contextMenus'],
        hostPatterns: const [],
      );
      expect(prompt.isEmpty, isTrue);
    });

    test('reports the developer-stated data collection', () {
      expect(
        describePermissions(
          permissions: const [],
          hostPatterns: const [],
          requiredDataCollection: const ['none'],
        ).dataCollectionLines,
        ["The developer says this extension doesn't require data collection."],
      );
      expect(
        describePermissions(
          permissions: const [],
          hostPatterns: const [],
          requiredDataCollection: const ['browsingActivity', 'searchTerms'],
        ).dataCollectionLines.single,
        contains('browsing activity, search terms'),
      );
    });
  });

  test('addedPermissions returns only what is new', () {
    expect(
      addedPermissions(
        granted: const ['tabs'],
        next: const ['tabs', 'history'],
      ),
      ['history'],
    );
  });
}

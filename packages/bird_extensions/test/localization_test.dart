import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

void main() {
  group('MessageCatalog', () {
    final catalog = MessageCatalog.fromJson({
      'extName': {'message': 'My Extension', 'description': 'ignored'},
      'greeting': {
        'message': 'Hello \$who\$, cost is \$\$5',
        'placeholders': {
          'who': {'content': 'world'},
        },
      },
    });

    test('replaces __MSG_ references, ignoring case in the name', () {
      expect(catalog.localize('__MSG_extName__'), 'My Extension');
      expect(catalog.localize('__MSG_EXTNAME__'), 'My Extension');
      expect(
        catalog.localize('Prefix __MSG_extName__ suffix'),
        'Prefix My Extension suffix',
      );
    });

    test('expands placeholders and escaped dollars', () {
      expect(catalog.message('greeting'), 'Hello world, cost is \$5');
    });

    test('exports entries for the shim with placeholders replaced', () {
      final entries = catalog.shimEntries();
      expect(entries['extname'], {'message': 'My Extension'});
      // $who$ became its content; $$ is left for the shim to unescape.
      expect(entries['greeting'], {'message': r'Hello world, cost is $$5'});
    });

    test('leaves unknown references alone', () {
      expect(catalog.localize('__MSG_missing__'), '__MSG_missing__');
      expect(catalog.localize('plain'), 'plain');
    });
  });

  group('chooseLocale', () {
    test('prefers an exact match, then the language, then the default', () {
      expect(
        chooseLocale(available: ['en', 'en_GB', 'fr'], preferred: ['en-GB']),
        'en_GB',
      );
      expect(chooseLocale(available: ['en', 'fr'], preferred: ['en-US']), 'en');
      expect(
        chooseLocale(
          available: ['de', 'fr'],
          preferred: ['en-US'],
          defaultLocale: 'fr',
        ),
        'fr',
      );
      expect(chooseLocale(available: ['en_GB'], preferred: ['en-US']), 'en_GB');
      expect(chooseLocale(available: ['de'], preferred: ['en-US']), isNull);
    });
  });
}

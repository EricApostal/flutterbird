import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

void main() {
  group('completeInline', () {
    const video = 'https://www.youtube.com/watch?v=1HxNu61aljk';

    test('fills only the host while only a host is typed', () {
      final completion = completeInline('you', video)!;
      expect(completion.text, 'youtube.com');
      expect(completion.target, 'https://www.youtube.com/');
    });

    test('fills the rest of the address once past the host', () {
      final completion = completeInline('youtube.com/wa', video)!;
      expect(completion.text, 'youtube.com/watch?v=1HxNu61aljk');
      expect(completion.target, video);
    });

    test('keeps exactly what was typed, and goes to the real address', () {
      final completion = completeInline('YouTube.com/WA', video)!;
      expect(completion.text, startsWith('YouTube.com/WA'));
      expect(completion.target, video);
    });

    test('follows someone typing www or the scheme', () {
      expect(completeInline('www.you', video)!.text, 'www.youtube.com');
      expect(
        completeInline('https://www.you', video)!.text,
        'https://www.youtube.com',
      );
    });

    test('a first letter does not match the scheme or www', () {
      expect(completeInline('h', video), isNull);
      expect(completeInline('http', video), isNull);
      expect(completeInline('w', video), isNull);
      expect(completeInline('w', 'https://wiki.test/')!.text, 'wiki.test');
      expect(completeInline('w', 'https://www.wiki.test/')!.text, 'wiki.test');
    });

    test('a bare site shows without its trailing slash', () {
      final completion = completeInline('exa', 'https://example.com/')!;
      expect(completion.text, 'example.com');
      expect(completeInline('example.com/', 'https://example.com/')!.text,
          'example.com/');
    });

    test('keeps the port and plain HTTP', () {
      expect(
        completeInline('local', 'http://localhost:3000/app')!.target,
        'http://localhost:3000/',
      );
    });

    test('completes nothing that does not begin with what was typed', () {
      expect(completeInline('tube', video), isNull);
      expect(completeInline('you tube', video), isNull);
      expect(completeInline('', video), isNull);
      expect(completeInline('abo', 'about:blank'), isNull);
      expect(completeInline('jav', 'javascript:alert(1)'), isNull);
    });

    test('never completes an address that hides its host behind a name', () {
      expect(completeInline('bank', 'https://bank.test@evil.test/'), isNull);
    });
  });

  group('allowsInlineCompletion', () {
    bool allows(String previous, String typed,
            {bool atEnd = true, bool composing = false}) =>
        allowsInlineCompletion(
          previous: previous,
          typed: typed,
          caretAtEnd: atEnd,
          composing: composing,
        );

    test('typing is completed', () {
      expect(allows('', 'y'), isTrue);
      expect(allows('youtube.com/wa', 'youtube.com/wat'), isTrue);
      expect(allows('https://old.test/', 'y'), isTrue);
    });

    test('deleting is not', () {
      // Backspace over the filled part leaves what had been typed.
      expect(allows('youtube.com/wa', 'youtube.com/wa'), isFalse);
      expect(allows('youtube', 'youtub'), isFalse);
      expect(allows('y', ''), isFalse);
    });

    test('nor is an edit in the middle or by an input method', () {
      expect(allows('yo', 'you', atEnd: false), isFalse);
      expect(allows('yo', 'you', composing: true), isFalse);
    });
  });

  group('arrangeSuggestions', () {
    ArrangedSuggestions<String> arrange(String typed, List<String> urls,
            {bool complete = true}) =>
        arrangeSuggestions(typed, urls, urlOf: (u) => u, complete: complete);

    test('the best address that completes leads', () {
      final result = arrange('git', [
        'https://example.com/git',
        'https://github.com/a',
        'https://gitlab.com/b',
      ]);
      expect(result.candidates.first, 'https://github.com/a');
      expect(result.candidates, hasLength(3));
      expect(result.completion!.text, 'github.com');
    });

    test('order is left alone when nothing completes or may', () {
      final urls = ['https://b.test/', 'https://a.test/'];
      expect(arrange('zzz', urls).candidates, urls);
      final held = arrange('a', urls, complete: false);
      expect(held.candidates, urls);
      expect(held.completion, isNull);
    });

    test('an address is listed once', () {
      expect(
        arrange('x', ['https://a.test/', 'https://a.test/']).candidates,
        hasLength(1),
      );
    });
  });

  group('matchRanges', () {
    List<String> bold(String text, String query) => [
          for (final r in matchRanges(text, query))
            text.substring(r.start, r.end),
        ];

    test('the whole query where the text holds it', () {
      expect(bold('youtube.com/watch?v=1', 'youtube.com/wa'),
          ['youtube.com/wa']);
    });

    test('otherwise its words, where they begin words', () {
      expect(bold('YouTube TV - Watch Live', 'youtube.com/wa'),
          ['YouTube', 'Wa']);
      expect(bold('Hawaii', 'wa x'), isEmpty);
    });

    test('overlapping parts are one', () {
      expect(bold('abcabc', 'ab abc'), ['abc']);
    });

    test('nothing for an empty query', () {
      expect(matchRanges('anything', '  '), isEmpty);
    });
  });

  test('displayAddress reads like the address bar', () {
    expect(displayAddress('https://www.example.com/'), 'example.com');
    expect(displayAddress('http://example.com/a/'), 'example.com/a/');
    expect(displayAddress('file:///tmp/a'), 'file:///tmp/a');
  });
}

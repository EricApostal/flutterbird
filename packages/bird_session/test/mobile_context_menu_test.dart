import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

void main() {
  var nextToken = 0;
  EngineMenuEntry action(
    String label, {
    bool enabled = true,
    bool checkable = false,
    bool checked = false,
  }) => EngineMenuEntry(
    label: label,
    token: ++nextToken,
    enabled: enabled,
    checkable: checkable,
    checked: checked,
  );
  const separator = EngineMenuEntry(label: '', kind: 'separator');

  List<String> labels(PageMenuPlan plan) => [
    for (final item in plan.items) item.label,
  ];

  test('a link is a card without what only a desktop has', () {
    final plan = planPageMenu('link', [
      action('Open Link in New Tab'),
      action('Open Link in New Window'),
      action('Open Link in Private Window'),
      separator,
      action('Copy Link'),
      action('Download Linked File'),
      action('Save Link As…'),
      separator,
      action('Inspect'),
    ]);
    expect(plan.style, PageMenuStyle.card);
    expect(plan.subject, PageMenuSubject.link);
    expect(labels(plan), [
      'Open in new tab',
      'Copy link address',
      'Download link',
    ]);
    expect(plan.items.map((item) => item.group), [0, 1, 1]);
  });

  test('a picture is a card, also when it is a link', () {
    final plan = planPageMenu('image', [
      action('Open Link in New Tab'),
      action('Copy Link'),
      separator,
      action('Open Image in New Tab'),
      action('Copy Image'),
      action('Save Image As…'),
    ]);
    expect(plan.style, PageMenuStyle.card);
    expect(plan.subject, PageMenuSubject.image);
    expect(labels(plan), contains('Download image'));
  });

  test('media says whether it is video or audio, and keeps ticks', () {
    final video = planPageMenu('media', [
      action('Pause'),
      action('Loop', checkable: true, checked: true),
      action('Picture in Picture'),
      action('Open Video in New Tab'),
    ]);
    expect(video.subject, PageMenuSubject.video);
    expect(labels(video), ['Pause', 'Loop', 'Open video in new tab']);
    expect(video.items[1].checked, isTrue);
    expect(video.items[0].checked, isNull);

    final audio = planPageMenu('media', [
      action('Play'),
      action('Copy Audio Address'),
    ]);
    expect(audio.subject, PageMenuSubject.audio);
  });

  test('selected text is a toolbar, in the order a phone has it', () {
    final plan = planPageMenu('page', [
      action('Copy'),
      separator,
      action('Search DuckDuckGo for “bird”'),
      action('Copy Link to Highlight', enabled: false),
      separator,
      action('Report Website Issue…'),
    ]);
    expect(plan.style, PageMenuStyle.toolbar);
    expect(labels(plan), ['Copy', 'Search']);
  });

  test('a text field offers editing, in toolbar order', () {
    final plan = planPageMenu('page', [
      action('Paste'),
      action('Paste and Match Style'),
      action('Select All'),
      action('Cut'),
      action('Copy'),
    ]);
    expect(plan.style, PageMenuStyle.toolbar);
    expect(labels(plan), [
      'Cut',
      'Copy',
      'Paste',
      'Select all',
      'Paste as plain text',
    ]);
  });

  test('selected text that is an address stays a toolbar', () {
    final plan = planPageMenu('link', [
      action('Open Link in New Tab'),
      action('Copy'),
    ]);
    expect(plan.style, PageMenuStyle.toolbar);
    expect(labels(plan), ['Copy', 'Open in new tab']);
  });

  test('an empty part of a page offers nothing', () {
    final plan = planPageMenu('page', [
      action('Back', enabled: false),
      action('Forward', enabled: false),
      action('Reload'),
      separator,
      action('View Page Source'),
      action('Take Screenshot...'),
    ]);
    expect(plan.style, PageMenuStyle.none);
    expect(plan.items, isEmpty);
  });

  test('submenus are flattened and entries without a token left out', () {
    final plan = planPageMenu('link', [
      EngineMenuEntry(
        label: 'More',
        kind: 'submenu',
        items: [action('Copy Link')],
      ),
      const EngineMenuEntry(label: 'Open Link in New Tab'),
    ]);
    expect(labels(plan), ['Copy link address']);
  });
}

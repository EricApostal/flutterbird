import 'package:bird_devtools/src/model/console_controller.dart';
import 'package:bird_devtools/src/model/dom.dart';
import 'package:bird_devtools/src/model/inspector_controller.dart';
import 'package:bird_devtools/src/model/network_controller.dart';
import 'package:bird_devtools/src/model/remote_value.dart';
import 'package:bird_devtools/src/model/styles.dart';
import 'package:bird_devtools/src/util/css_color.dart';
import 'package:bird_devtools/src/util/pretty_print.dart';
import 'package:bird_devtools/src/util/syntax.dart';
import 'package:flutter_test/flutter_test.dart';

DomNode element(String tag, [Map<String, String> attributes = const {}, DomNode? parent]) {
  final node = DomNode({
    'actor': '$tag${attributes.hashCode}',
    'nodeType': 1,
    'nodeName': tag.toUpperCase(),
    'namespaceURI': 'http://www.w3.org/1999/xhtml',
    'attrs': [
      for (final entry in attributes.entries) {'name': entry.key, 'value': entry.value},
    ],
  })..parent = parent;
  if (parent != null) (parent.children ??= []).add(node);
  return node;
}

AppliedRule rule(String selector, Map<String, String> declarations, {String? inheritedFrom}) => AppliedRule(
  actor: selector,
  isElementStyle: false,
  selectors: [selector],
  matchedSelectors: const {0},
  declarations: [
    for (final entry in declarations.entries)
      CssDeclaration(
        name: entry.key,
        value: entry.value.replaceAll(' !important', ''),
        important: entry.value.endsWith('!important'),
        inherits: const {'color', 'font-size'}.contains(entry.key),
      ),
  ],
  cssText: '',
  authoredText: '',
  inheritedFrom: inheritedFrom,
);

List<String> overridden(List<AppliedRule> rules) => [
  for (final r in rules)
    for (final d in r.declarations)
      if (d.overridden) '${r.selectorText} ${d.name}',
];

void main() {
  group('values', () {
    test('reads the special numbers and empty values', () {
      expect(RemoteValue.parse({'type': 'NaN'}).describe(), 'NaN');
      expect(RemoteValue.parse({'type': '-0'}).describe(), '-0');
      expect(RemoteValue.parse({'type': '-Infinity'}).describe(), '-Infinity');
      expect(RemoteValue.parse({'type': 'undefined'}).describe(), 'undefined');
      expect(RemoteValue.parse(null).describe(), 'null');
      expect(RemoteValue.parse({'type': 'BigInt', 'text': '10n'}).describe(), '10n');
      expect(RemoteValue.parse(42.0).describe(), '42');
      expect(RemoteValue.parse('a "b"\n').describe(quoteStrings: true), r'"a \"b\"\n"');
    });

    test('describes objects from their previews', () {
      final array = RemoteValue.parse({
        'type': 'object', 'class': 'Array', 'actor': 'a',
        'preview': {'kind': 'ArrayLike', 'length': 2, 'items': [1, 'two']},
      });
      expect(array.describe(), 'Array(2) [ 1, "two" ]');
      final element = RemoteValue.parse({
        'type': 'object', 'class': 'HTMLDivElement',
        'preview': {'kind': 'DOMNode', 'nodeType': 1, 'nodeName': 'div', 'attributes': {'id': 'x'}},
      });
      expect(element.describe(), '<div id="x">');
    });
  });

  group('DOM', () {
    test('makes selectors and paths that single an element out', () {
      final html = element('html');
      final body = element('body', const {}, html);
      final list = element('ul', const {'class': 'menu'}, body);
      element('li', const {'class': 'item'}, list);
      final second = element('li', const {'class': 'item'}, list);
      expect(second.cssSelector, 'body > ul.menu > li:nth-child(2)');
      expect(second.cssPath, 'html body ul.menu li.item');
      expect(second.xpath, '/html/body/ul/li[2]');
      final named = element('p', const {'id': '1st'}, body);
      expect(named.cssSelector, r'#\31 st');
    });

    test('reads attributes as typed', () {
      final attributes = InspectorController.parseAttributes('''class="a b" data-x='1' hidden title="&quot;q&quot;" n=2''');
      expect(
        {for (final a in attributes) a.name: a.value},
        {'class': 'a b', 'data-x': '1', 'hidden': '', 'title': '"q"', 'n': '2'},
      );
    });
  });

  group('cascade', () {
    test('later rules of the same property lose', () {
      final rules = [rule('#a', {'color': 'red'}), rule('.b', {'color': 'blue', 'margin': '1px'})];
      markOverriddenDeclarations(rules);
      expect(overridden(rules), ['.b color']);
    });

    test('importance beats order, and a shorthand covers its longhands', () {
      final rules = [
        rule('#a', {'margin-top': '1px', 'margin-left': '2px'}),
        rule('.b', {'margin': '3px'}),
        rule('p', {'margin-left': '4px !important'}),
      ];
      markOverriddenDeclarations(rules);
      // The shorthand still sets the sides nothing else claimed.
      expect(overridden(rules), ['#a margin-left']);
    });

    test('only inheritable declarations reach down', () {
      final inherited = rule('body', {'color': 'red', 'margin': '1px'}, inheritedFrom: 'n1');
      expect(inherited.declarations.map((d) => declarationReaches(inherited, d)), [true, false]);
      expect(ruleReachesElement(rule('body', {'margin': '1px'}, inheritedFrom: 'n1')), isFalse);
    });
  });

  group('colours', () {
    test('reads the ways CSS writes them', () {
      expect(parseCssColor('#0a84ff')!.toARGB32(), 0xFF0A84FF);
      expect(parseCssColor('#fff')!.toARGB32(), 0xFFFFFFFF);
      expect(parseCssColor('rgb(10, 132, 255)')!.toARGB32(), 0xFF0A84FF);
      expect(parseCssColor('rgb(10 132 255 / 50%)')!.toARGB32(), 0x800A84FF);
      expect(parseCssColor('hsl(0, 100%, 50%)')!.toARGB32(), 0xFFFF0000);
      expect(parseCssColor('rebeccapurple')!.toARGB32(), 0xFF663399);
      expect(parseCssColor('solid'), isNull);
      expect(parseCssColor('#12'), isNull);
    });

    test('writes them back the way they were written', () {
      final colour = parseCssColor('#0a84ff')!;
      expect(formatCssColor(colour, like: '#000'), '#0a84ff');
      expect(formatCssColor(colour, like: 'rgb(0,0,0)'), 'rgb(10, 132, 255)');
    });
  });

  group('pretty printing', () {
    String squeeze(String code) => code.replaceAll(RegExp(r'\s'), '');

    test('keeps every character of the code', () {
      const sources = [
        'function a(b,c){if(b){return c+1}else{return[1,2,{d:"}{;"}]}}var e=/[}{]\\//g;for(let i=0;i<3;i++){a(i,-1)}',
        'const t=`a ${'\$'}{b} {;`;x=a?b:c;y=!z;i++;j--;k+=-1;obj={a:1,b:{c:2}};/* c { */ // d }\nnext()',
        'class A extends B{static #x=1;get y(){return this.#x}}export default A;if(a)b();else c()',
        'a=b\n(function(){})\nreturn\nx',
      ];
      for (final source in sources) {
        final pretty = prettyPrintJavaScript(source);
        expect(squeeze(pretty.text), squeeze(source), reason: source);
      }
    });

    test('lays statements out on their own lines, remembering where from', () {
      final pretty = prettyPrintJavaScript('function a(){var b=1;return b}a();');
      expect(pretty.lines, ['function a() {', '  var b = 1;', '  return b', '}', 'a();']);
      expect(pretty.originalFor(2), (1, 13));
      expect(pretty.formattedLineFor(1, 20), 2);
      expect(pretty.formattedLineFor(1, 23), 3);
    });

    test('does not break a for header apart', () {
      final pretty = prettyPrintJavaScript('for(var i=0;i<2;i++){f()}');
      expect(pretty.lines.first, 'for (var i = 0; i < 2; i++) {');
    });

    test('spreads CSS out', () {
      final pretty = prettyPrintCss('a:hover,b{color:red;margin:0 0}@media (min-width:1px){c{d:e}}');
      expect(squeeze(pretty.text), squeeze('a:hover,b{color:red;margin:0 0}@media (min-width:1px){c{d:e}}'));
      expect(pretty.lines, contains('  color: red;'));
      expect(pretty.lines, contains('  margin: 0 0'));
    });
  });

  group('highlighting', () {
    test('carries comments and strings across lines', () {
      final tokens = highlightLines(['/* a', 'b */ var x = `c', 'd`;'], SyntaxLanguage.javascript);
      expect(tokens[1].first.kind, TokenKind.comment);
      expect(tokens[1].any((t) => t.kind == TokenKind.keyword), isTrue);
      expect(tokens[2].first.kind, TokenKind.string);
    });

    test('never overruns a line', () {
      const lines = ['<div a="1', "<script>let s = '", '</script><style>a{b:', '"c"}</style><!-- x'];
      for (final (index, tokens) in highlightLines(lines, SyntaxLanguage.html).indexed) {
        var end = 0;
        for (final token in tokens) {
          expect(token.start, greaterThanOrEqualTo(end), reason: lines[index]);
          expect(token.end, inInclusiveRange(token.start, lines[index].length), reason: lines[index]);
          end = token.end;
        }
      }
    });
  });

  group('other', () {
    test('reads error stacks', () {
      final stack = ConsoleController.parseErrorStack('go@http://x:8/a.js:3:9\n@(console):1:1\n@unknown:0:0\n');
      expect(stack.map((s) => '${s.function} ${s.location.url} ${s.location.line}'), [
        'go http://x:8/a.js 3',
        '<anonymous> (console) 1',
      ]);
    });

    test('quotes a request for the shell', () {
      final request = NetworkRequest(
        actor: 'a', resourceId: 1, url: "http://x/?q='", method: 'POST', started: DateTime(2026),
        causeType: 'fetch', isXhr: true, isNavigation: false, referrerPolicy: '', priority: 0, index: 0,
      )
        ..requestHeaders = const [HttpHeader('Cookie', "a=1; b=it's")]
        ..postData = r'$(rm)';
      expect(request.asCurl, "curl 'http://x/?q='\\''' \\\n  -H 'Cookie: a=1; b=it'\\''s' \\\n  --data-raw '\$(rm)'");
      expect(request.requestCookies.map((c) => c.name), ['a', 'b']);
    });
  });
}

import '../protocol/json.dart';

class CssDeclaration {
  CssDeclaration({
    required this.name,
    required this.value,
    this.important = false,
    this.isValid = true,
    this.isNameValid = true,
    this.isCustomProperty = false,
    this.inherits = false,
    this.enabled = true,
  });

  factory CssDeclaration.parse(Map<String, Object?> json) => CssDeclaration(
    name: json.str('name'),
    value: json.str('value'),
    important: json.str('priority') == 'important',
    isValid: json['isValid'] != false,
    isNameValid: json['isNameValid'] != false,
    isCustomProperty: json.flag('isCustomProperty'),
    inherits: json.flag('inherits'),
  );

  final String name;
  final String value;
  final bool important;
  final bool isValid;
  final bool isNameValid;
  final bool isCustomProperty;
  final bool inherits;

  /// Off for a declaration the user unticked, which is no longer in the page.
  bool enabled;

  /// Set when a rule of higher precedence declares the same property.
  bool overridden = false;

  String get text => '$name: $value${important ? ' !important' : ''};';
}

/// A rule that applies to the selected element, or to one it inherits from.
class AppliedRule {
  AppliedRule({
    required this.actor,
    required this.isElementStyle,
    required this.selectors,
    required this.matchedSelectors,
    required this.declarations,
    required this.cssText,
    required this.authoredText,
    this.styleSheetId,
    this.inheritedFrom,
    this.isSystem = false,
    this.ancestors = const [],
  });

  factory AppliedRule.parse(Map<String, Object?> entry) {
    final rule = entry.obj('rule');
    return AppliedRule(
      actor: rule.str('actor'),
      // The inline style is "rule type 100" in Firefox.
      isElementStyle: rule.integer('type') == 100,
      selectors: rule.strings('selectors'),
      matchedSelectors: {
        for (final index in entry.list('matchedSelectorIndexes'))
          if (index is num) index.toInt(),
      },
      declarations: rule
          .maps('declarations')
          .map(CssDeclaration.parse)
          .toList(),
      cssText: rule.str('cssText'),
      authoredText: rule.str('authoredText'),
      styleSheetId: rule.strOrNull('parentStyleSheet'),
      inheritedFrom: entry.strOrNull('inherited'),
      isSystem: entry.flag('isSystem') || rule.flag('isSystem'),
      ancestors: [
        for (final ancestor in rule.maps('ancestorData'))
          if (ancestor.str('conditionText').isNotEmpty)
            '@${ancestor.str('type', 'media')} ${ancestor.str('conditionText')}',
      ],
    );
  }

  final String actor;
  final bool isElementStyle;
  final List<String> selectors;
  final Set<int> matchedSelectors;
  final List<CssDeclaration> declarations;
  String cssText;
  final String authoredText;

  /// The stylesheet resource the rule is in, if it could be told.
  String? styleSheetId;

  /// The line of the sheet its selector is on, or zero if unknown.
  int sourceLine = 0;

  /// The node actor of the ancestor the rule reaches the element through.
  final String? inheritedFrom;
  final bool isSystem;
  final List<String> ancestors;

  String get selectorText =>
      isElementStyle ? 'element' : selectors.join(', ');

  /// What stays the same about a rule while its declarations are edited.
  String get identity =>
      '${inheritedFrom ?? ''}|${styleSheetId ?? ''}|$selectorText';
}

const Map<String, List<String>> _shorthands = {
  'margin': ['margin-top', 'margin-right', 'margin-bottom', 'margin-left'],
  'padding': ['padding-top', 'padding-right', 'padding-bottom', 'padding-left'],
  'inset': ['top', 'right', 'bottom', 'left'],
  'gap': ['row-gap', 'column-gap'],
  'overflow': ['overflow-x', 'overflow-y'],
  'flex': ['flex-grow', 'flex-shrink', 'flex-basis'],
  'flex-flow': ['flex-direction', 'flex-wrap'],
  'background': [
    'background-color',
    'background-image',
    'background-repeat',
    'background-position-x',
    'background-position-y',
    'background-size',
    'background-attachment',
    'background-origin',
    'background-clip',
  ],
  'background-position': ['background-position-x', 'background-position-y'],
  'font': [
    'font-style',
    'font-variant',
    'font-weight',
    'font-stretch',
    'font-size',
    'line-height',
    'font-family',
  ],
  'list-style': ['list-style-type', 'list-style-position', 'list-style-image'],
  'text-decoration': [
    'text-decoration-line',
    'text-decoration-style',
    'text-decoration-color',
    'text-decoration-thickness',
  ],
  'outline': ['outline-color', 'outline-style', 'outline-width'],
  'transition': [
    'transition-property',
    'transition-duration',
    'transition-timing-function',
    'transition-delay',
  ],
  'animation': [
    'animation-name',
    'animation-duration',
    'animation-timing-function',
    'animation-delay',
    'animation-iteration-count',
    'animation-direction',
    'animation-fill-mode',
    'animation-play-state',
  ],
  'border-radius': [
    'border-top-left-radius',
    'border-top-right-radius',
    'border-bottom-right-radius',
    'border-bottom-left-radius',
  ],
  'place-items': ['align-items', 'justify-items'],
  'place-content': ['align-content', 'justify-content'],
  'place-self': ['align-self', 'justify-self'],
};

const List<String> _sides = ['top', 'right', 'bottom', 'left'];
const List<String> _borderParts = ['width', 'style', 'color'];

/// The longhand properties that declaring [name] sets.
List<String> longhandsOf(String name) {
  if (name == 'border') {
    return [
      for (final side in _sides)
        for (final part in _borderParts) 'border-$side-$part',
    ];
  }
  for (final part in _borderParts) {
    if (name == 'border-$part') {
      return [for (final side in _sides) 'border-$side-$part'];
    }
  }
  for (final side in _sides) {
    if (name == 'border-$side') {
      return [for (final part in _borderParts) 'border-$side-$part'];
    }
  }
  return _shorthands[name] ?? [name];
}

/// Whether a declaration of an ancestor reaches the element.
bool _reaches(AppliedRule rule, CssDeclaration declaration) =>
    rule.inheritedFrom == null ||
    declaration.inherits ||
    declaration.isCustomProperty;

/// Marks the declarations that lose the cascade. [rules] come from the server
/// in order of precedence, highest first.
void markOverriddenDeclarations(List<AppliedRule> rules) {
  final claimed = <String>{};
  for (final rule in rules) {
    for (final declaration in rule.declarations) {
      declaration.overridden = false;
    }
  }
  for (final important in [true, false]) {
    for (final rule in rules) {
      // Within a rule, the later declaration wins.
      for (final declaration in rule.declarations.reversed) {
        if (declaration.important != important) continue;
        if (!declaration.enabled || !declaration.isValid) continue;
        if (!_reaches(rule, declaration)) continue;
        // A pseudo-element's rules do not compete with the element's own.
        final scope = _pseudoElementOf(rule);
        final names = [
          for (final name in longhandsOf(declaration.name)) '$scope$name',
        ];
        if (names.every(claimed.contains)) {
          declaration.overridden = true;
        } else {
          claimed.addAll(names);
        }
      }
    }
  }
}

final RegExp _pseudoElement = RegExp(r'::?(before|after|marker|placeholder|selection|first-line|first-letter|backdrop)\b');

String _pseudoElementOf(AppliedRule rule) {
  for (final index in rule.matchedSelectors) {
    if (index < rule.selectors.length) {
      final match = _pseudoElement.firstMatch(rule.selectors[index]);
      if (match != null) return '${match.group(1)}|';
    }
  }
  return '';
}

/// Whether an inherited rule has anything to show for the element.
bool ruleReachesElement(AppliedRule rule) =>
    rule.inheritedFrom == null ||
    rule.declarations.any((declaration) => _reaches(rule, declaration));

bool declarationReaches(AppliedRule rule, CssDeclaration declaration) =>
    _reaches(rule, declaration);

import '../protocol/json.dart';

class DomAttribute {
  const DomAttribute(this.name, this.value);
  final String name;
  final String value;
}

/// A node of the page's document, as the walker describes it.
class DomNode {
  DomNode(this.form) {
    update(form);
  }

  static const int elementNode = 1;
  static const int textNode = 3;
  static const int commentNode = 8;
  static const int documentNode = 9;
  static const int doctypeNode = 10;
  static const int fragmentNode = 11;

  Map<String, Object?> form;

  late String actor;
  late int nodeType;
  late String nodeName;
  late String? nodeValue;
  late List<DomAttribute> attributes;
  late int childCount;
  late String displayType;
  late bool isDisplayed;
  late bool isScrollable;

  DomNode? parent;

  /// Null until the children have been asked for.
  List<DomNode>? children;

  void update(Map<String, Object?> next) {
    form = next;
    actor = next.str('actor');
    nodeType = next.integer('nodeType');
    nodeName = next.str('nodeName');
    nodeValue = next.strOrNull('nodeValue');
    attributes = [
      for (final attribute in next.maps('attrs'))
        DomAttribute(attribute.str('name'), attribute.str('value')),
    ];
    childCount = next.integer('numChildren');
    displayType = next.str('displayType');
    isDisplayed = next.flag('isDisplayed');
    isScrollable = next.flag('isScrollable');
  }

  bool get isPseudoElement => form.flag('isPseudoElement');
  bool get isShadowRoot => form.flag('isShadowRoot');
  bool get isDocument => form.flag('isTopLevelDocument');
  bool get isElement => nodeType == elementNode && !isPseudoElement;
  bool get isText => nodeType == textNode && !isPseudoElement;
  bool get isComment => nodeType == commentNode;

  /// The tag as HTML writes it: the server names HTML elements in capitals.
  String get tag {
    if (isPseudoElement) return nodeName;
    final namespace = form.str('namespaceURI');
    if (namespace.endsWith('xhtml') && nodeName == nodeName.toUpperCase()) {
      return nodeName.toLowerCase();
    }
    return nodeName;
  }

  String? attribute(String name) {
    for (final attribute in attributes) {
      if (attribute.name == name) return attribute.value;
    }
    return null;
  }

  String get id => attribute('id') ?? '';

  List<String> get classes => (attribute('class') ?? '')
      .split(RegExp(r'\s+'))
      .where((name) => name.isNotEmpty)
      .toList();

  /// Short text that is shown on the element's own line, as Firefox does for an
  /// element with nothing in it but a little text.
  DomNode? get inlineText {
    final children = this.children;
    if (childCount != 1 || children == null || children.length != 1) {
      return null;
    }
    final child = children.single;
    final text = child.nodeValue;
    if (!child.isText || text == null) return null;
    if (text.length > 60 || text.contains('\n')) return null;
    return child;
  }

  /// This node and what holds it, outermost first, without the document.
  List<DomNode> get path {
    final nodes = <DomNode>[];
    for (DomNode? node = this; node != null; node = node.parent) {
      if (!node.isDocument) nodes.add(node);
    }
    return nodes.reversed.toList();
  }

  /// `tag#id.class1.class2`, as breadcrumbs and highlighters label it.
  String get selectorLabel {
    final label = StringBuffer(tag);
    if (id.isNotEmpty) label.write('#$id');
    for (final name in classes) {
      label.write('.$name');
    }
    return label.toString();
  }

  Iterable<DomNode> get elementSiblings =>
      parent?.children?.where((node) => node.isElement) ?? const [];

  /// A selector that finds this element and no other, as short as one can be
  /// made from ids and positions.
  String get cssSelector {
    if (!isElement) return parent?.cssSelector ?? '';
    final parts = <String>[];
    for (DomNode? node = this; node != null && node.isElement;) {
      if (node.id.isNotEmpty) {
        parts.add('#${escapeCssIdentifier(node.id)}');
        break;
      }
      if (node.tag == 'html' || node.tag == 'body' || node.tag == 'head') {
        parts.add(node.tag);
        break;
      }
      var part = node.tag;
      final siblings = node.elementSiblings.toList();
      final classes = node.classes;
      final unique = classes.where(
        (name) =>
            siblings.where((other) => other.classes.contains(name)).length == 1,
      );
      if (unique.isNotEmpty) {
        part += '.${escapeCssIdentifier(unique.first)}';
      } else if (siblings.where((other) => other.tag == node!.tag).length > 1) {
        part += ':nth-child(${siblings.indexOf(node) + 1})';
      }
      parts.add(part);
      node = node.parent;
    }
    return parts.reversed.join(' > ');
  }

  /// The element's tags from the root, as Firefox's "CSS Path" copies.
  String get cssPath => [
    for (final node in path)
      if (node.isElement) node.selectorLabel,
  ].join(' ');

  String get xpath {
    final parts = <String>[];
    for (DomNode? node = this; node != null && !node.isDocument;) {
      if (node.isElement && node.id.isNotEmpty) {
        parts.add('//*[@id="${node.id}"]');
        return parts.reversed.join('/');
      }
      final siblings = node.parent?.children ?? [node];
      bool alike(DomNode other) => node!.isElement
          ? other.isElement && other.tag == node.tag
          : other.nodeType == node.nodeType;
      final same = siblings.where(alike).toList();
      var step = switch (node.nodeType) {
        textNode => 'text()',
        commentNode => 'comment()',
        _ => node.tag,
      };
      if (same.length > 1) step += '[${same.indexOf(node) + 1}]';
      parts.add(step);
      node = node.parent;
    }
    return '/${parts.reversed.join('/')}';
  }
}

/// [identifier] as a selector has to write it.
String escapeCssIdentifier(String identifier) {
  final out = StringBuffer();
  for (var i = 0; i < identifier.length; i++) {
    final unit = identifier.codeUnitAt(i);
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLetter =
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
    final plain = isLetter || unit == 0x5F || unit == 0x2D || unit >= 0x80;
    if (isDigit && (i == 0 || (i == 1 && identifier[0] == '-'))) {
      out.write('\\${unit.toRadixString(16)} ');
    } else if (plain || isDigit) {
      out.writeCharCode(unit);
    } else {
      out.write('\\${identifier[i]}');
    }
  }
  return out.toString();
}

import '../protocol/json.dart';

/// What a value in the page is.
enum RemoteKind { undefined, nul, boolean, number, string, bigint, object }

/// A value in the page, as the protocol describes it: a primitive, or a grip
/// that names an object and says a little about it.
class RemoteValue {
  const RemoteValue._(this.kind, {this.value, this.form = const {}});

  static const RemoteValue undefined = RemoteValue._(RemoteKind.undefined);
  static const RemoteValue nul = RemoteValue._(RemoteKind.nul);

  const RemoteValue.string(String text)
    : kind = RemoteKind.string,
      value = text,
      form = const {};

  factory RemoteValue.parse(Object? json) {
    if (json == null) return nul;
    if (json is bool) return RemoteValue._(RemoteKind.boolean, value: json);
    if (json is num) return RemoteValue._(RemoteKind.number, value: json);
    if (json is String) return RemoteValue._(RemoteKind.string, value: json);
    if (json is! Map<String, Object?>) return undefined;
    switch (json['type']) {
      case 'undefined':
        return undefined;
      case 'null':
        return nul;
      case 'NaN':
        return const RemoteValue._(RemoteKind.number, value: double.nan);
      case 'Infinity':
        return const RemoteValue._(RemoteKind.number, value: double.infinity);
      case '-Infinity':
        return const RemoteValue._(
          RemoteKind.number,
          value: double.negativeInfinity,
        );
      case '-0':
        return const RemoteValue._(RemoteKind.number, value: -0.0);
      case 'BigInt':
        return RemoteValue._(RemoteKind.bigint, value: json.str('text'));
      case 'longString':
        return RemoteValue._(RemoteKind.string, value: json.str('initial'));
      default:
        return RemoteValue._(RemoteKind.object, form: json);
    }
  }

  final RemoteKind kind;

  /// A primitive's value. For a bigint, its digits.
  final Object? value;

  /// An object's grip.
  final Map<String, Object?> form;

  bool get isObject => kind == RemoteKind.object;
  bool get isString => kind == RemoteKind.string;

  /// The actor that answers for the object, or null for a grip that only
  /// describes one.
  String? get actor => form.strOrNull('actor');

  String get className => form.str('class', 'Object');

  Map<String, Object?> get preview => form.obj('preview');

  String get previewKind => preview.str('kind');

  bool get isDomNode => previewKind == 'DOMNode';

  bool get isElement => isDomNode && preview.integer('nodeType') == 1;

  bool get isFunction =>
      isObject &&
      (className == 'Function' || className.endsWith('Function')) &&
      previewKind.isEmpty;

  bool get isError => previewKind == 'Error' || form.flag('isError');

  /// The node a DOM node's grip stands for, which the inspector can find.
  Map<String, Object?>? get contentDomReference =>
      form.mapOrNull('contentDomReference');

  /// Whether there is anything to see by opening it.
  bool get isExpandable => isObject && actor != null;

  /// A number as JavaScript writes it.
  static String formatNumber(num number) {
    if (number is double) {
      if (number.isNaN) return 'NaN';
      if (number.isInfinite) return number < 0 ? '-Infinity' : 'Infinity';
      if (number == 0 && number.isNegative) return '-0';
      if (number == number.truncateToDouble() && number.abs() < 1e21) {
        return number.toInt().toString();
      }
    }
    return number.toString();
  }

  /// The value as one line of plain text, as copying it gives.
  String describe({bool quoteStrings = false, int depth = 0}) {
    switch (kind) {
      case RemoteKind.undefined:
        return 'undefined';
      case RemoteKind.nul:
        return 'null';
      case RemoteKind.boolean:
        return '$value';
      case RemoteKind.number:
        return formatNumber(value! as num);
      case RemoteKind.bigint:
        final text = '$value';
        return text.endsWith('n') ? text : '${text}n';
      case RemoteKind.string:
        return quoteStrings ? quote(value! as String) : value! as String;
      case RemoteKind.object:
        return _describeObject(depth);
    }
  }

  static String quote(String text) {
    final escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t')
        .replaceAll('"', r'\"');
    return '"$escaped"';
  }

  String _describeObject(int depth) {
    final preview = this.preview;
    if (isDomNode) {
      final name = preview.str('nodeName').toLowerCase();
      if (preview.integer('nodeType') != 1) return name;
      final attributes = preview.obj('attributes');
      final text = StringBuffer('<$name');
      for (final entry in attributes.entries) {
        text.write(' ${entry.key}=${quote('${entry.value}')}');
      }
      text.write('>');
      return text.toString();
    }
    if (isError) {
      final name = preview.str('name', className);
      final message = preview.str('message');
      return message.isEmpty ? name : '$name: $message';
    }
    if (form['displayString'] is String) return form.str('displayString');
    if (isFunction) {
      return 'function ${form.str('displayName', form.str('name'))}()';
    }
    if (className == 'Date' && preview['timestamp'] is num) {
      return 'Date ${DateTime.fromMillisecondsSinceEpoch(preview.integer('timestamp')).toIso8601String()}';
    }
    if (depth > 0) return className;
    switch (previewKind) {
      case 'ArrayLike':
        final items = preview.list('items');
        final length = preview.integer('length');
        if (!preview.containsKey('items')) return '$className($length)';
        final shown = items
            .map(
              (item) => RemoteValue.parse(
                item,
              ).describe(quoteStrings: true, depth: depth + 1),
            )
            .join(', ');
        return '$className($length) [ $shown ]';
      case 'MapLike':
        return '$className(${preview.integer('size')})';
      case 'Object':
        final properties = preview.obj('ownProperties');
        if (properties.isEmpty) return className;
        final shown = properties.entries
            .take(10)
            .map((entry) {
              final descriptor = entry.value;
              final value =
                  descriptor is Map<String, Object?> &&
                      descriptor.containsKey('value')
                  ? RemoteValue.parse(
                      descriptor['value'],
                    ).describe(quoteStrings: true, depth: depth + 1)
                  : '…';
              return '${entry.key}: $value';
            })
            .join(', ');
        return '$className { $shown }';
    }
    return className;
  }
}

/// One property of an object: a value, or the functions that stand for one.
class RemoteProperty {
  const RemoteProperty({
    required this.name,
    this.value,
    this.getter,
    this.setter,
    this.enumerable = true,
    this.writable = true,
  });

  factory RemoteProperty.parse(String name, Object? descriptor) {
    final map = descriptor is Map<String, Object?>
        ? descriptor
        : const <String, Object?>{};
    RemoteValue? read(String key) =>
        map.containsKey(key) ? RemoteValue.parse(map[key]) : null;
    return RemoteProperty(
      name: name,
      value: read('value'),
      getter: read('get'),
      setter: read('set'),
      enumerable: map['enumerable'] != false,
      writable: map['writable'] != false,
    );
  }

  final String name;
  final RemoteValue? value;
  final RemoteValue? getter;
  final RemoteValue? setter;
  final bool enumerable;
  final bool writable;
}

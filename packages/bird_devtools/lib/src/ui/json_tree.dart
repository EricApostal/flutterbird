import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'menu.dart';
import 'theme.dart';

/// [text] as JSON, if it is JSON worth showing as a tree.
Object? tryDecodeJson(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
  try {
    return jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
}

/// Parsed JSON as rows that open, as Firefox shows a JSON response.
class DtJsonTree extends StatefulWidget {
  const DtJsonTree({super.key, required this.value, this.filter = '', this.shrinkWrap = false});

  final Object? value;
  final String filter;
  final bool shrinkWrap;

  @override
  State<DtJsonTree> createState() => _DtJsonTreeState();
}

class _JsonRow {
  const _JsonRow(this.path, this.name, this.value, this.depth);
  final String path;
  final String name;
  final Object? value;
  final int depth;

  bool get expandable =>
      (value is Map && (value! as Map<Object?, Object?>).isNotEmpty) ||
      (value is List && (value! as List<Object?>).isNotEmpty);
}

class _DtJsonTreeState extends State<DtJsonTree> {
  // What differs from the starting state, which opens the first two levels.
  final Set<String> _toggled = {};

  bool _open(_JsonRow row) => (row.depth < 2) != _toggled.contains(row.path);

  List<_JsonRow> _rows() {
    final rows = <_JsonRow>[];
    final needle = widget.filter.toLowerCase();

    bool matches(String name, Object? value) {
      if (needle.isEmpty) return true;
      if (name.toLowerCase().contains(needle)) return true;
      if (value is Map<Object?, Object?>) return value.entries.any((e) => matches('${e.key}', e.value));
      if (value is List<Object?>) return value.any((e) => matches('', e));
      return '$value'.toLowerCase().contains(needle);
    }

    void visit(String path, String name, Object? value, int depth) {
      if (rows.length > 5000 || !matches(name, value)) return;
      final row = _JsonRow(path, name, value, depth);
      rows.add(row);
      if (!row.expandable || (needle.isEmpty && !_open(row))) return;
      if (value is Map<Object?, Object?>) {
        for (final entry in value.entries) {
          visit('$path\u0001${entry.key}', '${entry.key}', entry.value, depth + 1);
        }
      } else if (value is List<Object?>) {
        for (final (index, item) in value.indexed) {
          visit('$path\u0001$index', '$index', item, depth + 1);
        }
      }
    }

    final value = widget.value;
    if (value is Map<Object?, Object?>) {
      for (final entry in value.entries) {
        visit('${entry.key}', '${entry.key}', entry.value, 0);
      }
    } else if (value is List<Object?>) {
      for (final (index, item) in value.indexed) {
        visit('$index', '$index', item, 0);
      }
    } else {
      visit('', '', value, 0);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: rows.length,
      itemBuilder: (context, index) => _row(context, rows[index]),
    );
  }

  Widget _row(BuildContext context, _JsonRow row) {
    final colors = context.dt;
    final value = row.value;
    final (String text, Color color) = switch (value) {
      null => ('null', colors.textDim),
      String() => (jsonEncode(value), colors.objectString),
      num() || bool() => ('$value', colors.objectNumber),
      Map<Object?, Object?>() => (value.isEmpty ? '{}' : '{…}', colors.textDim),
      List<Object?>() => (value.isEmpty ? '[]' : '[…]  ${value.length}', colors.textDim),
      _ => ('$value', colors.textStrong),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: row.expandable
          ? () => setState(() => _toggled.contains(row.path) ? _toggled.remove(row.path) : _toggled.add(row.path))
          : null,
      onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, [
        DtMenuItem(
          'Copy Value',
          onSelected: () => Clipboard.setData(ClipboardData(text: value is String ? value : const JsonEncoder.withIndent('  ').convert(value))),
        ),
        DtMenuItem(
          'Copy All',
          onSelected: () => Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(widget.value))),
        ),
      ]),
      child: Padding(
        padding: EdgeInsets.only(left: 8 + row.depth * 14, right: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 12,
              child: row.expandable
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: DtIcon(_open(row) || widget.filter.isNotEmpty ? DtGlyph.twistyDown : DtGlyph.twistyRight, size: 8, color: colors.textDim),
                    )
                  : null,
            ),
            if (row.name.isNotEmpty) Text('${row.name}: ', style: context.monoStyle(color: colors.objectKey)),
            Flexible(
              child: Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: context.monoStyle(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'theme.dart';

sealed class DtMenuEntry {
  const DtMenuEntry();
}

class DtMenuItem extends DtMenuEntry {
  const DtMenuItem(
    this.label, {
    this.onSelected,
    this.shortcut = '',
    this.enabled = true,
    this.checked,
    this.glyph,
    this.submenu,
  }) : isSeparator = false;

  const DtMenuItem.separator()
    : label = '',
      onSelected = null,
      shortcut = '',
      enabled = false,
      checked = null,
      glyph = null,
      submenu = null,
      isSeparator = true;

  final String label;
  final VoidCallback? onSelected;
  final String shortcut;
  final bool enabled;

  /// Null for an item that cannot be ticked.
  final bool? checked;
  final DtGlyph? glyph;
  final List<DtMenuEntry>? submenu;
  final bool isSeparator;

  bool get canActivate => !isSeparator && enabled;
}

/// Shows [entries] where a context menu belongs, at [globalPosition].
Future<void> showDtMenu(
  BuildContext context,
  Offset globalPosition,
  List<DtMenuEntry> entries,
) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || entries.isEmpty) return Future.value();
  final colors = context.dt;
  final done = Completer<void>();
  final previousFocus = FocusManager.instance.primaryFocus;
  late final OverlayEntry entry;
  void close() {
    if (done.isCompleted) return;
    entry.remove();
    entry.dispose();
    previousFocus?.requestFocus();
    done.complete();
  }

  final box = overlay.context.findRenderObject()! as RenderBox;
  final anchor = box.globalToLocal(globalPosition);
  entry = OverlayEntry(
    builder: (_) => DtTheme(
      colors: colors,
      child: _MenuLayer(entries: entries, anchor: anchor, onClose: close),
    ),
  );
  overlay.insert(entry);
  return done.future;
}

/// Shows [entries] under the widget of [context].
Future<void> showDtMenuBelow(BuildContext context, List<DtMenuEntry> entries) {
  final box = context.findRenderObject();
  if (box is! RenderBox) return Future.value();
  return showDtMenu(context, box.localToGlobal(Offset(0, box.size.height + 1)), entries);
}

const double _rowHeight = 22;
const double _separatorHeight = 9;

class _Level {
  _Level(this.entries, this.position, [this.alternativeRight]);
  final List<DtMenuEntry> entries;
  final Offset position;

  /// Where the right edge goes if the menu does not fit to the right.
  final double? alternativeRight;
  int highlighted = -1;

  double get height {
    var height = 10.0;
    for (final entry in entries) {
      height += (entry as DtMenuItem).isSeparator ? _separatorHeight : _rowHeight;
    }
    return height;
  }

  double offsetOf(int index) {
    var offset = 5.0;
    for (var i = 0; i < index; i++) {
      offset += (entries[i] as DtMenuItem).isSeparator ? _separatorHeight : _rowHeight;
    }
    return offset;
  }

  double get width {
    var longest = 0.0;
    for (final entry in entries.cast<DtMenuItem>()) {
      final length = entry.label.length * 6.6 + (entry.shortcut.isEmpty ? 0 : entry.shortcut.length * 7 + 24);
      if (length > longest) longest = length;
    }
    return (longest + 56).clamp(160.0, 420.0);
  }
}

class _MenuLayer extends StatefulWidget {
  const _MenuLayer({required this.entries, required this.anchor, required this.onClose});

  final List<DtMenuEntry> entries;
  final Offset anchor;
  final VoidCallback onClose;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> {
  late final List<_Level> _levels = [_Level(widget.entries, widget.anchor)];
  final FocusNode _focus = FocusNode(debugLabel: 'menu');
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Offset _place(_Level level) {
    var x = level.position.dx;
    var y = level.position.dy;
    if (x + level.width > _size.width - 4) {
      x = (level.alternativeRight ?? level.position.dx) - level.width;
    }
    if (y + level.height > _size.height - 4) y = _size.height - level.height - 4;
    return Offset(x < 2 ? 2 : x, y < 2 ? 2 : y);
  }

  void _openSubmenu(int depth, int index) {
    final level = _levels[depth];
    final item = level.entries[index] as DtMenuItem;
    _levels.removeRange(depth + 1, _levels.length);
    if (item.submenu != null && item.enabled) {
      final origin = _place(level);
      _levels.add(
        _Level(
          item.submenu!,
          Offset(origin.dx + level.width - 3, origin.dy + level.offsetOf(index) - 5),
          origin.dx + 3,
        ),
      );
    }
  }

  void _hover(int depth, int index) {
    setState(() {
      _levels[depth].highlighted = index;
      _openSubmenu(depth, index);
    });
  }

  void _activate(int depth, int index) {
    final item = _levels[depth].entries[index] as DtMenuItem;
    if (!item.canActivate) return;
    if (item.submenu != null) {
      _hover(depth, index);
      return;
    }
    widget.onClose();
    item.onSelected?.call();
  }

  void _move(int step) {
    final level = _levels.last;
    var index = level.highlighted;
    for (var i = 0; i < level.entries.length; i++) {
      index = (index + step) % level.entries.length;
      if ((level.entries[index] as DtMenuItem).canActivate) break;
    }
    setState(() => level.highlighted = index);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    final depth = _levels.length - 1;
    final level = _levels.last;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.arrowLeft && depth > 0) {
      setState(() => _levels.removeLast());
    } else if (level.highlighted >= 0 &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space)) {
      _activate(depth, level.highlighted);
    } else if (key == LogicalKeyboardKey.arrowRight && level.highlighted >= 0) {
      final item = level.entries[level.highlighted] as DtMenuItem;
      if (item.submenu != null) {
        setState(() => _openSubmenu(depth, level.highlighted));
        _move(1);
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          return Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => widget.onClose(),
                ),
              ),
              for (var depth = 0; depth < _levels.length; depth++)
                Positioned(
                  left: _place(_levels[depth]).dx,
                  top: _place(_levels[depth]).dy,
                  width: _levels[depth].width,
                  child: Container(
                    constraints: BoxConstraints(maxHeight: _size.height - 8),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.popup,
                      border: Border.all(color: colors.popupBorder),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 5)),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < _levels[depth].entries.length; i++)
                            _row(context, depth, i),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, int depth, int index) {
    final colors = context.dt;
    final item = _levels[depth].entries[index] as DtMenuItem;
    if (item.isSeparator) {
      return Container(
        height: _separatorHeight,
        alignment: Alignment.center,
        child: Container(height: 1, color: colors.splitter),
      );
    }
    final highlighted = _levels[depth].highlighted == index && item.enabled;
    final foreground = !item.enabled
        ? colors.textDim.withValues(alpha: 0.55)
        : highlighted
        ? const Color(0xFFFFFFFF)
        : colors.textStrong;
    return MouseRegion(
      onEnter: (_) => _hover(depth, index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _activate(depth, index),
        child: Container(
          height: _rowHeight,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: highlighted ? const Color(0xFF0060DF) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Center(
                  child: item.checked == true
                      ? DtIcon(DtGlyph.check, size: 11, color: foreground)
                      : item.glyph != null
                      ? DtIcon(item.glyph!, size: 13, color: foreground)
                      : null,
                ),
              ),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.uiStyle(color: foreground),
                ),
              ),
              if (item.shortcut.isNotEmpty)
                Text(
                  item.shortcut,
                  style: context.uiStyle(color: highlighted ? foreground : colors.textDim),
                ),
              SizedBox(
                width: 16,
                child: item.submenu != null
                    ? DtIcon(DtGlyph.chevronRight, size: 10, color: foreground)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

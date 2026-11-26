import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'theme.dart';

sealed class BirdMenuEntry {
  const BirdMenuEntry();
}

class BirdMenuItem extends BirdMenuEntry {
  const BirdMenuItem(
    this.label, {
    this.onSelected,
    this.shortcut = '',
    this.enabled = true,
    this.checked,
    this.glyph,
    this.submenu,
  }) : isSeparator = false;

  const BirdMenuItem.separator()
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
  final BirdGlyph? glyph;
  final List<BirdMenuEntry>? submenu;
  final bool isSeparator;

  bool get canActivate => !isSeparator && enabled;
}

/// Shows [entries] where a context menu belongs, at [globalPosition].
Future<void> showBirdMenu(
  BuildContext context,
  Offset globalPosition,
  List<BirdMenuEntry> entries, {
  double? alignRight,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final shown = tidyMenuEntries(entries);
  if (overlay == null || shown.isEmpty) return Future.value();
  final compact = BirdMenuTheme.isCompact(context);
  final textStyle = context.birdText(size: compact ? BirdTextSize.small : BirdTextSize.body);
  final colors = context.bird;
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
  final right = alignRight == null ? null : box.globalToLocal(Offset(alignRight, 0)).dx;
  final metrics = _Metrics(rowHeight: compact ? 22 : 26, textStyle: textStyle);
  entry = OverlayEntry(
    builder: (_) => BirdTheme(
      colors: colors,
      child: BirdMenuTheme(
        compact: compact,
        // A press in a menu leaves a field's caret where it is.
        child: TextFieldTapRegion(
          child: _MenuLayer(
            entries: shown,
            anchor: anchor,
            anchorRight: right,
            metrics: metrics,
            onClose: close,
            // The window may go with the menu still up.
            onGone: () {
              if (!done.isCompleted) done.complete();
            },
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  return done.future;
}

/// Shows [entries] under the widget of [context]. A menu with no room to the
/// right of its button's left edge ends at its right edge instead.
Future<void> showBirdMenuBelow(BuildContext context, List<BirdMenuEntry> entries) {
  final box = context.findRenderObject();
  if (box is! RenderBox) return Future.value();
  final origin = box.localToGlobal(Offset(0, box.size.height + 1));
  return showBirdMenu(context, origin, entries, alignRight: origin.dx + box.size.width);
}

/// [entries] without separators that separate nothing.
List<BirdMenuEntry> tidyMenuEntries(List<BirdMenuEntry> entries) {
  final tidy = <BirdMenuEntry>[];
  for (final entry in entries) {
    final separator = (entry as BirdMenuItem).isSeparator;
    if (separator && (tidy.isEmpty || (tidy.last as BirdMenuItem).isSeparator)) continue;
    tidy.add(entry);
  }
  if (tidy.isNotEmpty && (tidy.last as BirdMenuItem).isSeparator) tidy.removeLast();
  return tidy;
}

class _Metrics {
  _Metrics({required this.rowHeight, required this.textStyle});

  final double rowHeight;
  final TextStyle textStyle;

  double measure(String text) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// How roomy menus are. The tools keep theirs [compact].
class BirdMenuTheme extends InheritedWidget {
  const BirdMenuTheme({super.key, required this.compact, required super.child});

  final bool compact;

  static bool isCompact(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BirdMenuTheme>()?.compact ?? false;

  @override
  bool updateShouldNotify(BirdMenuTheme oldWidget) => oldWidget.compact != compact;
}

/// The menus that are open, which what is under them has to know: a press in
/// a menu is not a press outside the popover the menu came from.
abstract final class BirdMenus {
  static int _open = 0;
  static bool get isOpen => _open > 0;
}

double _textSize(BuildContext context) => BirdMenuTheme.isCompact(context) ? BirdTextSize.small : BirdTextSize.body;

const double _separatorHeight = 9;

class _Level {
  _Level(this.entries, this.position, this.metrics, [this.alternativeRight]) : width = _widthOf(entries, metrics);

  final List<BirdMenuEntry> entries;
  final Offset position;
  final _Metrics metrics;

  /// Where the right edge goes if the menu does not fit to the right.
  final double? alternativeRight;
  final double width;
  int highlighted = -1;

  double _extent(int index) => (entries[index] as BirdMenuItem).isSeparator ? _separatorHeight : metrics.rowHeight;

  double get height {
    var height = 10.0;
    for (var i = 0; i < entries.length; i++) {
      height += _extent(i);
    }
    return height;
  }

  double offsetOf(int index) {
    var offset = 5.0;
    for (var i = 0; i < index; i++) {
      offset += _extent(i);
    }
    return offset;
  }

  static double _widthOf(List<BirdMenuEntry> entries, _Metrics metrics) {
    var longest = 0.0;
    for (final entry in entries.cast<BirdMenuItem>()) {
      final shortcut = entry.shortcut.isEmpty ? 0 : metrics.measure(entry.shortcut) + 28;
      final length = metrics.measure(entry.label) + shortcut;
      if (length > longest) longest = length;
    }
    // The tick column, the submenu column, the margins and the border.
    return (longest + 22 + 16 + 8 + 2 + 10).ceilToDouble().clamp(160.0, 420.0);
  }
}

class _MenuLayer extends StatefulWidget {
  const _MenuLayer({
    required this.entries,
    required this.anchor,
    required this.anchorRight,
    required this.metrics,
    required this.onClose,
    required this.onGone,
  });

  final List<BirdMenuEntry> entries;
  final Offset anchor;
  final double? anchorRight;
  final _Metrics metrics;
  final VoidCallback onClose;
  final VoidCallback onGone;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> {
  late final List<_Level> _levels = [
    _Level(widget.entries, widget.anchor, widget.metrics, widget.anchorRight),
  ];
  final FocusNode _focus = FocusNode(debugLabel: 'menu');
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    BirdMenus._open++;
    _focus.requestFocus();
  }

  @override
  void dispose() {
    BirdMenus._open--;
    widget.onGone();
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
    final item = level.entries[index] as BirdMenuItem;
    _levels.removeRange(depth + 1, _levels.length);
    if (item.submenu != null && item.enabled) {
      final origin = _place(level);
      final submenu = tidyMenuEntries(item.submenu!);
      if (submenu.isEmpty) return;
      _levels.add(
        _Level(
          submenu,
          Offset(origin.dx + level.width - 3, origin.dy + level.offsetOf(index) - 5),
          widget.metrics,
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
    final item = _levels[depth].entries[index] as BirdMenuItem;
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
      if ((level.entries[index] as BirdMenuItem).canActivate) break;
    }
    setState(() => level.highlighted = index);
  }

  // Typing a letter goes to the next item that starts with it, as on macOS.
  void _jumpTo(String character) {
    final level = _levels.last;
    for (var step = 1; step <= level.entries.length; step++) {
      final index = (level.highlighted + step) % level.entries.length;
      final item = level.entries[index] as BirdMenuItem;
      if (item.canActivate && item.label.toLowerCase().startsWith(character.toLowerCase())) {
        setState(() => level.highlighted = index);
        return;
      }
    }
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
      final item = level.entries[level.highlighted] as BirdMenuItem;
      if (item.submenu != null) {
        setState(() => _openSubmenu(depth, level.highlighted));
        _move(1);
      }
    } else if (event.character case final character? when character.trim().isNotEmpty) {
      _jumpTo(character);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
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
                      color: colors.panel,
                      border: Border.all(color: colors.panelBorder),
                      borderRadius: BorderRadius.circular(BirdRadius.menu),
                      boxShadow: [
                        BoxShadow(color: colors.shadow, blurRadius: 14, offset: const Offset(0, 5)),
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
    final colors = context.bird;
    final item = _levels[depth].entries[index] as BirdMenuItem;
    if (item.isSeparator) {
      return Container(
        height: _separatorHeight,
        alignment: Alignment.center,
        child: Container(height: 1, color: colors.separator),
      );
    }
    final highlighted = _levels[depth].highlighted == index && item.enabled;
    final foreground = !item.enabled
        ? colors.textDisabled
        : highlighted
        ? colors.onSelection
        : colors.text;
    return MouseRegion(
      onEnter: (_) => _hover(depth, index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _activate(depth, index),
        child: Container(
          height: widget.metrics.rowHeight,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: highlighted ? colors.selection : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Center(
                  child: item.checked == true
                      ? BirdIcon(BirdGlyph.check, size: 11, color: foreground)
                      : item.glyph != null
                      ? BirdIcon(item.glyph!, size: 13, color: foreground)
                      : null,
                ),
              ),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.birdText(color: foreground, size: _textSize(context)),
                ),
              ),
              if (item.shortcut.isNotEmpty)
                Text(
                  item.shortcut,
                  style: context.birdText(color: highlighted ? foreground : colors.textSecondary, size: _textSize(context)),
                ),
              SizedBox(
                width: 16,
                child: item.submenu != null
                    ? BirdIcon(BirdGlyph.chevronRight, size: 10, color: foreground)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

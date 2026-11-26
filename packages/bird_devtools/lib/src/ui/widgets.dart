import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/settings.dart';
import 'icons.dart';
import 'menu.dart';
import 'theme.dart';

export 'package:bird_ui/bird_ui.dart' show BirdHover, BirdScrollBehavior, BirdTextInput, BirdTooltip;

// The parts every interface of the browser is made of live in bird_ui. What is
// here is the tools' own, which is denser than the rest.
typedef DtHover = BirdHover;
typedef DtTooltip = BirdTooltip;
typedef DtTextInput = BirdTextInput;
typedef DtScrollBehavior = BirdScrollBehavior;

/// A square toolbar button with an icon.
class DtIconButton extends StatelessWidget {
  const DtIconButton(
    this.glyph, {
    super.key,
    this.tooltip = '',
    this.onPressed,
    this.active = false,
    this.enabled = true,
    this.color,
    this.width = 24,
    this.height = 22,
    this.iconSize = 14,
  });

  final DtGlyph glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool enabled;
  final Color? color;
  final double width;
  final double height;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final usable = enabled && onPressed != null;
    return DtTooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: DtHover(
          onTap: usable ? onPressed : null,
          builder: (context, hovered) => Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? colors.toolbarActive
                  : hovered && usable
                  ? colors.toolbarHover
                  : null,
              borderRadius: BorderRadius.circular(2),
            ),
            child: DtIcon(
              glyph,
              size: iconSize,
              color: !usable
                  ? colors.textDim.withValues(alpha: 0.45)
                  : active
                  ? colors.accent
                  : color ?? colors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// A button with words, as in dialogs and empty states.
class DtButton extends StatelessWidget {
  const DtButton(
    this.label, {
    super.key,
    this.onPressed,
    this.primary = false,
    this.glyph,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final DtGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final enabled = onPressed != null;
    final foreground = primary ? context.bird.onAccent : colors.textStrong;
    return DtHover(
      onTap: onPressed,
      builder: (context, hovered) => Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: primary
                ? (hovered && enabled ? context.bird.accentHover : context.bird.accent)
                : (hovered && enabled ? colors.toolbarActive : colors.toolbarHover),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph case final glyph?) ...[
                DtIcon(glyph, size: 14, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(label, style: context.uiStyle(color: foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A word in a toolbar that is on or off, such as "Errors" or "CSS".
class DtChip extends StatelessWidget {
  const DtChip(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
    this.tooltip = '',
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return DtTooltip(
      message: tooltip,
      child: DtHover(
        onTap: onTap,
        builder: (context, hovered) => Container(
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: colors.isDark ? 0.18 : 0.12)
                : hovered
                ? colors.toolbarHover
                : null,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            label,
            style: context.uiStyle(color: selected ? colors.accent : colors.text),
          ),
        ),
      ),
    );
  }
}

class DtCheckbox extends StatelessWidget {
  const DtCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.size = 12,
    this.radio = false,
    this.tooltip = '',
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final double size;
  final bool radio;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: value && !radio ? context.bird.accent : colors.inputBackground,
        border: Border.all(
          color: value ? context.bird.accent : colors.splitterStrong,
        ),
        shape: radio ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radio ? null : BorderRadius.circular(2),
      ),
      alignment: Alignment.center,
      child: !value
          ? null
          : radio
          ? Container(
              width: size - 6,
              height: size - 6,
              decoration: BoxDecoration(color: context.bird.accent, shape: BoxShape.circle),
            )
          : DtIcon(DtGlyph.check, size: size - 2, color: const Color(0xFFFFFFFF)),
    );
    return DtTooltip(
      message: tooltip,
      child: Semantics(
        checked: value,
        label: label ?? tooltip,
        child: DtHover(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          builder: (context, hovered) => Opacity(
            opacity: onChanged == null ? 0.5 : 1,
            child: label == null
                ? box
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      box,
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(label!, style: context.uiStyle(), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// A button that opens a menu below itself.
class DtDropdown extends StatelessWidget {
  const DtDropdown({
    super.key,
    required this.label,
    required this.entries,
    this.enabled = true,
    this.tooltip = '',
  });

  final String label;
  final List<DtMenuEntry> Function() entries;
  final bool enabled;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return DtTooltip(
      message: tooltip,
      child: Builder(
        builder: (context) => DtHover(
          onTap: enabled ? () => showDtMenuBelow(context, entries()) : null,
          builder: (context, hovered) => Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: hovered && enabled ? colors.toolbarHover : null,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: context.uiStyle(color: enabled ? colors.text : colors.textDim.withValues(alpha: 0.5)),
                ),
                const SizedBox(width: 3),
                DtIcon(DtGlyph.chevronDown, size: 10, color: colors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip of controls along the top of a pane.
class DtToolbar extends StatelessWidget {
  const DtToolbar({
    super.key,
    required this.children,
    this.height = 28,
    this.color,
    this.bottomBorder = true,
    this.topBorder = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final List<Widget> children;
  final double height;
  final Color? color;
  final bool bottomBorder;
  final bool topBorder;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final side = BorderSide(color: colors.splitter);
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? colors.toolbar,
        border: Border(
          bottom: bottomBorder ? side : BorderSide.none,
          top: topBorder ? side : BorderSide.none,
        ),
      ),
      child: Row(children: children),
    );
  }
}

class DtToolbarSeparator extends StatelessWidget {
  const DtToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: context.dt.splitter,
  );
}

/// The filter and search boxes of the toolbars: a glyph, a field, and a button
/// that empties it.
class DtSearchBox extends StatefulWidget {
  const DtSearchBox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.placeholder,
    this.onSubmitted,
    this.glyph = DtGlyph.filter,
    this.focusNode,
    this.trailing = const [],
    this.height = 20,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final void Function(String value, bool backwards)? onSubmitted;
  final String placeholder;
  final DtGlyph glyph;
  final FocusNode? focusNode;
  final List<Widget> trailing;
  final double height;

  @override
  State<DtSearchBox> createState() => _DtSearchBoxState();
}

class _DtSearchBoxState extends State<DtSearchBox> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void didUpdateWidget(DtSearchBox old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return ListenableBuilder(
      listenable: _node,
      builder: (context, child) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: colors.inputBackground,
          border: Border.all(color: _node.hasFocus ? colors.accent : colors.inputBorder),
          borderRadius: BorderRadius.circular(2),
        ),
        child: child,
      ),
      child: Row(
        children: [
          const SizedBox(width: 5),
          DtIcon(widget.glyph, size: 11, color: colors.textDim),
          const SizedBox(width: 5),
          Expanded(
            child: DtTextInput(
              controller: _controller,
              focusNode: _node,
              placeholder: widget.placeholder,
              onChanged: widget.onChanged,
              onKey: (event) {
                if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  if (_controller.text.isEmpty) return KeyEventResult.ignored;
                  _clear();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter && widget.onSubmitted != null) {
                  widget.onSubmitted!(_controller.text, HardwareKeyboard.instance.isShiftPressed);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.text.isEmpty
                ? const SizedBox(width: 2)
                : DtIconButton(DtGlyph.close, width: 16, height: 16, iconSize: 9, tooltip: 'Clear', onPressed: _clear),
          ),
          ...widget.trailing,
        ],
      ),
    );
  }
}

/// Two panes with a line between them that can be dragged. One pane keeps its
/// size as the whole changes, and the other takes the rest.
class DtSplit extends StatefulWidget {
  const DtSplit({
    super.key,
    required this.first,
    required this.second,
    required this.initialSize,
    this.axis = Axis.horizontal,
    this.sizeSecond = true,
    this.minSize = 80,
    this.minOther = 80,
    this.settings,
    this.settingKey,
    this.showSecond = true,
  });

  final Widget first;
  final Widget second;
  final double initialSize;
  final Axis axis;

  /// Whether the size is the second pane's, rather than the first's.
  final bool sizeSecond;
  final double minSize;
  final double minOther;
  final DevToolsSettings? settings;
  final String? settingKey;
  final bool showSecond;

  @override
  State<DtSplit> createState() => _DtSplitState();
}

class _DtSplitState extends State<DtSplit> {
  late double _size = widget.settings != null && widget.settingKey != null
      ? widget.settings!.number(widget.settingKey!, widget.initialSize)
      : widget.initialSize;
  double _shown = 0;

  // The panes keep their state while the split moves or loses one of them.
  final GlobalKey _firstKey = GlobalKey();
  final GlobalKey _secondKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final first = KeyedSubtree(key: _firstKey, child: widget.first);
    if (!widget.showSecond) return first;
    final second = KeyedSubtree(key: _secondKey, child: widget.second);
    final colors = context.dt;
    final horizontal = widget.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final most = (total - widget.minOther - 1).clamp(0.0, double.infinity);
        final least = widget.minSize.clamp(0.0, most);
        final size = _size.clamp(least, most).toDouble();
        _shown = size;
        Widget pane(Widget child, double? extent) => extent == null
            ? Expanded(child: ClipRect(child: child))
            : SizedBox(
                width: horizontal ? extent : null,
                height: horizontal ? null : extent,
                child: ClipRect(child: child),
              );
        final line = Container(
          width: horizontal ? 1 : null,
          height: horizontal ? null : 1,
          color: colors.splitter,
        );
        final children = [
          pane(first, widget.sizeSecond ? null : size),
          line,
          pane(second, widget.sizeSecond ? size : null),
        ];
        final edge = widget.sizeSecond ? total - size - 1 : size;
        final handle = MouseRegion(
          cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (_) => _size = _shown,
            onPanUpdate: (details) {
              final delta = horizontal ? details.delta.dx : details.delta.dy;
              setState(() {
                _size = (_size + (widget.sizeSecond ? -delta : delta)).clamp(least, most).toDouble();
              });
            },
            onPanEnd: (_) {
              if (widget.settingKey case final key?) {
                widget.settings?.set(key, _size, quiet: true);
              }
            },
          ),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: horizontal
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
            Positioned(
              left: horizontal ? edge - 3 : 0,
              top: horizontal ? 0 : edge - 3,
              right: horizontal ? null : 0,
              bottom: horizontal ? 0 : null,
              width: horizontal ? 7 : null,
              height: horizontal ? null : 7,
              child: handle,
            ),
          ],
        );
      },
    );
  }
}

/// The tabs along the top of a sidebar.
class DtSidebarTabs extends StatelessWidget {
  const DtSidebarTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.leading,
    this.trailing,
  });

  /// Each tab's id and label.
  final List<(String, String)> tabs;
  final String selected;
  final ValueChanged<String> onSelect;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return Container(
      height: 25,
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(bottom: BorderSide(color: colors.splitter)),
      ),
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (id, label) in tabs)
                    DtHover(
                      onTap: () => onSelect(id),
                      builder: (context, hovered) => Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: id == selected
                              ? colors.body
                              : hovered
                              ? colors.toolbarHover
                              : null,
                          border: Border(
                            top: BorderSide(
                              width: 2,
                              color: id == selected
                                  ? colors.accent
                                  : hovered
                                  ? colors.splitterStrong
                                  : const Color(0x00000000),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            label,
                            style: context.uiStyle(color: id == selected ? colors.accent : colors.text),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A heading that shows and hides what is under it.
class DtAccordion extends StatelessWidget {
  const DtAccordion({
    super.key,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.actions = const [],
    this.header = true,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final List<Widget> actions;

  /// Whether the heading has a toolbar's background.
  final bool header;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DtHover(
          onTap: onToggle,
          builder: (context, hovered) => Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: header ? colors.toolbar : null,
              border: Border(bottom: BorderSide(color: colors.splitter)),
            ),
            child: Row(
              children: [
                DtIcon(expanded ? DtGlyph.twistyDown : DtGlyph.twistyRight, size: 9, color: colors.textDim),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    title,
                    style: context.uiStyle(color: colors.textStrong, weight: header ? FontWeight.w500 : FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.splitter))),
            child: child,
          ),
      ],
    );
  }
}

/// What a pane says when it has nothing to show.
class DtEmptyState extends StatelessWidget {
  const DtEmptyState(this.message, {super.key, this.actions = const [], this.detail = ''});

  final String message;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center, style: context.uiStyle(color: colors.textDim, size: 13)),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(detail, textAlign: TextAlign.center, style: context.uiStyle(color: colors.textDim, size: 11)),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

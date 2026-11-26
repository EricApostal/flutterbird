import 'package:flutter/widgets.dart';

import '../model/settings.dart';
import '../ui/icons.dart';
import '../ui/inline_editor.dart';
import '../ui/menu.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class _Device {
  const _Device(this.name, this.width, this.height);
  final String name;
  final double width;
  final double height;
}

const List<_Device> _devices = [
  _Device('iPhone SE', 375, 667),
  _Device('iPhone 16', 393, 852),
  _Device('iPhone 16 Pro Max', 440, 956),
  _Device('Pixel 9', 412, 923),
  _Device('Galaxy S25', 360, 780),
  _Device('iPad mini', 744, 1133),
  _Device('iPad Air', 820, 1180),
  _Device('iPad Pro 13"', 1032, 1376),
  _Device('Laptop', 1366, 768),
  _Device('Desktop 1080p', 1920, 1080),
];

/// Responsive Design Mode: the page in a viewport of any size. The page is
/// really resized, so its media queries and layout respond.
class ResponsiveView extends StatefulWidget {
  const ResponsiveView({super.key, required this.settings, required this.onClose, required this.child});

  final DevToolsSettings settings;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<ResponsiveView> createState() => _ResponsiveViewState();
}

class _ResponsiveViewState extends State<ResponsiveView> {
  late double _width = widget.settings.number('responsive.width', 393);
  late double _height = widget.settings.number('responsive.height', 852);
  late String _device = widget.settings.text('responsive.device', 'Responsive');
  String? _editing;

  static const double _least = 120;

  void _set(double width, double height, [String device = 'Responsive']) {
    setState(() {
      _width = width.clamp(_least, 4000).roundToDouble();
      _height = height.clamp(_least, 4000).roundToDouble();
      _device = device;
    });
    widget.settings
      ..set('responsive.width', _width, quiet: true)
      ..set('responsive.height', _height, quiet: true)
      ..set('responsive.device', _device, quiet: true);
  }

  Widget _dimension(BuildContext context, String id, double value, ValueChanged<double> apply) {
    final colors = context.dt;
    if (_editing == id) {
      return DtInlineEditor(
        initial: '${value.round()}',
        minWidth: 46,
        onCancel: () => setState(() => _editing = null),
        onCommit: (text, end) {
          setState(() => _editing = null);
          final next = double.tryParse(text.trim());
          if (next != null) apply(next);
        },
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _editing = id),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Container(
          width: 46,
          height: 19,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.inputBackground, border: Border.all(color: colors.inputBorder)),
          child: Text('${value.round()}', style: context.monoStyle(color: colors.textStrong)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return ColoredBox(
      color: colors.isDark ? const Color(0xFF0C0C0D) : const Color(0xFFEDEDF0),
      child: Column(
        children: [
          DtToolbar(
            height: 30,
            children: [
              const SizedBox(width: 4),
              DtDropdown(
                label: _device,
                entries: () => [
                  DtMenuItem('Responsive', checked: _device == 'Responsive', onSelected: () => _set(_width, _height)),
                  const DtMenuItem.separator(),
                  for (final device in _devices)
                    DtMenuItem(
                      device.name,
                      shortcut: '${device.width.round()} × ${device.height.round()}',
                      checked: _device == device.name,
                      onSelected: () => _set(device.width, device.height, device.name),
                    ),
                ],
              ),
              const Spacer(),
              _dimension(context, 'width', _width, (value) => _set(value, _height)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text('×', style: context.uiStyle())),
              _dimension(context, 'height', _height, (value) => _set(_width, value)),
              const SizedBox(width: 6),
              DtIconButton(DtGlyph.rotate, tooltip: 'Rotate viewport', onPressed: () => _set(_height, _width, _device)),
              const Spacer(),
              DtIconButton(DtGlyph.close, iconSize: 11, tooltip: 'Close Responsive Design Mode', onPressed: widget.onClose),
              const SizedBox(width: 4),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // A viewport larger than the room there is gets cut down to it.
                final width = _width.clamp(_least, (constraints.maxWidth - 28).clamp(_least, 4000)).toDouble();
                final height = _height.clamp(_least, (constraints.maxHeight - 28).clamp(_least, 4000)).toDouble();
                Widget handle({required bool horizontal, required bool vertical, required MouseCursor cursor, required DtGlyph? glyph}) => MouseRegion(
                  cursor: cursor,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => _set(width, height),
                    onPanUpdate: (details) => _set(
                      // The viewport is centred, so each side moves half as far.
                      _width + (horizontal ? details.delta.dx * 2 : 0),
                      _height + (vertical ? details.delta.dy : 0),
                    ),
                    child: Center(
                      child: Container(
                        width: horizontal && !vertical ? 4 : vertical && !horizontal ? 28 : 8,
                        height: vertical && !horizontal ? 4 : horizontal && !vertical ? 28 : 8,
                        decoration: BoxDecoration(color: colors.textDim, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                );
                final left = (constraints.maxWidth - width) / 2;
                const top = 10.0;
                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(border: Border.all(color: colors.splitterStrong)),
                        child: ClipRect(child: widget.child),
                      ),
                    ),
                    Positioned(
                      left: left + width + 2,
                      top: top,
                      width: 12,
                      height: height,
                      child: handle(horizontal: true, vertical: false, cursor: SystemMouseCursors.resizeLeftRight, glyph: null),
                    ),
                    Positioned(
                      left: left,
                      top: top + height + 2,
                      width: width,
                      height: 12,
                      child: handle(horizontal: false, vertical: true, cursor: SystemMouseCursors.resizeUpDown, glyph: null),
                    ),
                    Positioned(
                      left: left + width + 2,
                      top: top + height + 2,
                      width: 12,
                      height: 12,
                      child: handle(horizontal: true, vertical: true, cursor: SystemMouseCursors.resizeUpLeftDownRight, glyph: null),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

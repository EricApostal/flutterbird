import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'menu.dart';
import 'pressable.dart';
import 'theme.dart';

/// A control with its words beside it, which press it too.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.control, required this.label, required this.description});

  final Widget control;
  final String? label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    if (label == null) return control;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        control,
        const SizedBox(width: 8),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.birdText()),
                if (description case final description?)
                  Text(
                    description,
                    style: context.birdText(color: context.bird.textSecondary, size: BirdTextSize.small),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BirdCheckbox extends StatelessWidget {
  const BirdCheckbox({super.key, required this.value, required this.onChanged, this.label, this.description});

  final bool value;

  /// Null disables.
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return Semantics(
      checked: value,
      child: BirdPressable(
        onPressed: onChanged == null ? null : () => onChanged!(!value),
        builder: (context, state) => Opacity(
          opacity: state.enabled ? 1 : 0.4,
          child: _Labelled(
            label: label,
            description: description,
            control: BirdFocusRing(
              visible: state.focused,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value
                      ? (state.hovered ? colors.accentHover : colors.accent)
                      : (state.hovered ? colors.controlHover : colors.inputBackground),
                  borderRadius: BorderRadius.circular(BirdRadius.control),
                  border: value ? null : Border.all(color: colors.inputBorder),
                ),
                child: value ? BirdIcon(BirdGlyph.check, size: 12, color: colors.onAccent) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of several, of which one is chosen.
class BirdRadio<T> extends StatelessWidget {
  const BirdRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.label,
    this.description,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    final selected = value == groupValue;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: BirdPressable(
        onPressed: onChanged == null ? null : () => onChanged!(value),
        builder: (context, state) => Opacity(
          opacity: state.enabled ? 1 : 0.4,
          child: _Labelled(
            label: label,
            description: description,
            control: BirdFocusRing(
              visible: state.focused,
              radius: 8,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.hovered && !selected ? colors.controlHover : colors.inputBackground,
                  border: Border.all(color: selected ? colors.accent : colors.inputBorder, width: selected ? 5 : 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On or off, taking effect at once.
class BirdSwitch extends StatelessWidget {
  const BirdSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return Semantics(
      toggled: value,
      child: BirdPressable(
        onPressed: onChanged == null ? null : () => onChanged!(!value),
        semanticLabel: semanticLabel,
        builder: (context, state) => Opacity(
          opacity: state.enabled ? 1 : 0.4,
          child: BirdFocusRing(
            visible: state.focused,
            radius: 9,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 32,
              height: 18,
              padding: const EdgeInsets.all(2),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value
                    ? (state.hovered ? colors.accentHover : colors.accent)
                    : (state.hovered ? colors.controlActive : colors.controlHover),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: value ? const Color(0x00000000) : colors.inputBorder.withValues(alpha: 0.7),
                ),
              ),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? colors.onAccent : colors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class BirdOption<T> {
  const BirdOption(this.value, this.label);

  final T value;
  final String label;
}

/// A button that shows what is chosen, and a menu to choose from.
class BirdSelect<T> extends StatelessWidget {
  const BirdSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.small = false,
    this.semanticLabel,
  });

  final T value;
  final List<BirdOption<T>> options;
  final ValueChanged<T>? onChanged;
  final bool small;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    final chosen = options.where((option) => option.value == value).firstOrNull;
    return Builder(
      builder: (context) => BirdPressable(
        semanticLabel: semanticLabel,
        onPressed: onChanged == null
            ? null
            : () => showBirdMenuBelow(context, [
                for (final option in options)
                  BirdMenuItem(
                    option.label,
                    checked: option.value == value,
                    onSelected: () {
                      if (option.value != value) onChanged!(option.value);
                    },
                  ),
              ]),
        builder: (context, state) => Opacity(
          opacity: state.enabled ? 1 : 0.4,
          child: BirdFocusRing(
            visible: state.focused,
            child: Container(
              height: small ? 24 : 30,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: state.pressed
                    ? colors.controlActive
                    : state.hovered
                    ? colors.controlHover
                    : colors.control,
                borderRadius: BorderRadius.circular(BirdRadius.control),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      chosen?.label ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.birdText(size: small ? BirdTextSize.small : BirdTextSize.body),
                    ),
                  ),
                  const SizedBox(width: 6),
                  BirdIcon(BirdGlyph.chevronUpDown, size: 11, color: colors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

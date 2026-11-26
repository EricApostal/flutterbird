import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

/// A screen of settings: a large title that folds into the bar as the list is
/// scrolled, over groups of rows.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Scaffold(
      backgroundColor: colors.settingsBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            backgroundColor: colors.settingsBackground,
            surfaceTintColor: Colors.transparent,
            leading: const BackButton(),
            title: Text(title),
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rows that belong together: each on a surface of its own, a hair apart, the
/// outer corners of the first and last rounded.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, this.title, super.key});

  final String? title;
  final List<Widget> children;

  static const Radius _outer = Radius.circular(20);
  static const Radius _inner = Radius.circular(5);

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final title?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.accent,
                ),
              ),
            ),
          for (final (index, child) in children.indexed)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 2),
              child: Material(
                color: colors.settingsTile,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.vertical(
                  top: index == 0 ? _outer : _inner,
                  bottom: index == children.length - 1 ? _outer : _inner,
                ),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

/// One row: what it is, what it is set to, and what pressing it does.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// In place of [icon].
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final before =
        leading ??
        (icon == null ? null : Icon(icon, color: colors.textSecondary));
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              if (before != null) ...[before, const SizedBox(width: 18)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, color: colors.text),
                    ),
                    if (subtitle case final subtitle?)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: SettingsRow(
        title: title,
        subtitle: subtitle,
        icon: icon,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// One choice of several.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: SettingsRow(
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: trailing,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? colors.accent : colors.textSecondary,
        ),
      ),
    );
  }
}

/// Every component of the library on one page, to look at while changing it:
/// show a [BirdGallery] anywhere under a `BirdApp`. `test/screenshots_test.dart`
/// takes pictures of it.
library;

import 'package:flutter/widgets.dart';

import 'bird_ui.dart';

class BirdGallery extends StatefulWidget {
  const BirdGallery({super.key});

  @override
  State<BirdGallery> createState() => _BirdGalleryState();
}

class _BirdGalleryState extends State<BirdGallery> {
  bool _check = true;
  bool _switch = true;
  int _radio = 1;
  String _select = 'ask';

  Widget _section(String name, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: context.birdText(size: BirdTextSize.headline, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return ColoredBox(
      color: colors.toolbar,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('Buttons', [
              BirdButton.primary('Primary', onPressed: () {}),
              BirdButton('Secondary', onPressed: () {}),
              BirdButton('Delete', kind: BirdButtonKind.danger, onPressed: () {}),
              BirdButton('Ghost', kind: BirdButtonKind.ghost, onPressed: () {}),
              const BirdButton('Disabled', onPressed: null),
              BirdButton('Small', small: true, glyph: BirdGlyph.plus, onPressed: () {}),
              BirdLink('A link', onPressed: () {}),
            ]),
            _section('Toolbar', [
              for (final glyph in [BirdGlyph.back, BirdGlyph.forward, BirdGlyph.reload, BirdGlyph.star])
                BirdToolbarButton(glyph: glyph, onPressed: () {}),
              BirdToolbarButton(glyph: BirdGlyph.starFilled, color: colors.accent, onPressed: () {}),
              BirdBadge(label: '3', child: BirdToolbarButton(glyph: BirdGlyph.download, onPressed: () {})),
              const BirdToolbarButton(glyph: BirdGlyph.forward, onPressed: null),
              BirdToolbarButton(glyph: BirdGlyph.menu, active: true, onPressed: () {}),
            ]),
            _section('Icons', [
              for (final glyph in BirdGlyph.values.skipWhile((glyph) => glyph != BirdGlyph.back)) BirdIcon(glyph),
            ]),
            _section('Fields', [
              const SizedBox(width: 220, child: BirdTextField(placeholder: 'Placeholder')),
              const SizedBox(width: 220, child: BirdTextField(initialValue: 'Wrong', errorText: 'That is not an address.')),
              SizedBox(width: 220, child: BirdSearchField(onChanged: (_) {})),
              const SizedBox(width: 140, child: BirdTextField(initialValue: 'Disabled', enabled: false)),
            ]),
            _section('Controls', [
              BirdCheckbox(value: _check, label: 'Checkbox', onChanged: (v) => setState(() => _check = v)),
              BirdCheckbox(value: false, label: 'Unchecked', onChanged: (_) {}),
              for (final value in [1, 2])
                BirdRadio<int>(value: value, groupValue: _radio, label: 'Radio $value', onChanged: (v) => setState(() => _radio = v)),
              BirdSwitch(value: _switch, onChanged: (v) => setState(() => _switch = v)),
              BirdSwitch(value: false, onChanged: (_) {}),
              BirdSelect<String>(
                value: _select,
                options: const [BirdOption('ask', 'Always ask'), BirdOption('allow', 'Allow'), BirdOption('block', 'Block')],
                onChanged: (v) => setState(() => _select = v),
              ),
            ]),
            _section('Progress', [
              const SizedBox(width: 220, child: BirdProgressBar(value: 0.6)),
              const BirdSpinner(),
            ]),
            _section('Messages', [
              for (final (kind, message) in const [
                (BirdMessageKind.info, 'An update is ready.'),
                (BirdMessageKind.success, 'Added the extension.'),
                (BirdMessageKind.warning, 'This connection is not secure.'),
                (BirdMessageKind.error, 'The file could not be saved.'),
              ])
                SizedBox(width: 300, child: BirdMessageBar(message, kind: kind)),
            ]),
            _section('Panel', [
              BirdPanel(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BirdPanelHeader('Extensions', onClose: () {}),
                    const SizedBox(height: 4),
                    BirdListRow(
                      leading: const BirdIcon(BirdGlyph.extension),
                      title: 'uBlock Origin',
                      subtitle: '1.58.0',
                      trailing: BirdSwitch(value: true, onChanged: (_) {}),
                      onPressed: () {},
                    ),
                    BirdListRow(leading: const BirdIcon(BirdGlyph.gear), title: 'Manage extensions', onPressed: () {}),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              BirdDialog(
                width: 380,
                leading: const BirdIcon(BirdGlyph.extension, size: 20),
                title: 'Add uBlock Origin?',
                message: 'It asks to read and change your data on all websites.',
                actions: [
                  BirdDialogAction('Cancel', onPressed: () {}),
                  BirdDialogAction('Add', kind: BirdButtonKind.primary, onPressed: () {}),
                ],
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

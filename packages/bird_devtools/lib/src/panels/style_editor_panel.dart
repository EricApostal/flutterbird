import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/session.dart';
import '../model/style_editor_controller.dart';
import '../ui/code_editor.dart';
import '../ui/icons.dart';
import '../ui/menu.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../util/pretty_print.dart';
import '../util/syntax.dart';

/// The Style Editor: the page's style sheets, edited with the page restyling
/// as they are typed.
class StyleEditorPanel extends StatefulWidget {
  const StyleEditorPanel({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<StyleEditorPanel> createState() => _StyleEditorPanelState();
}

class _StyleEditorPanelState extends State<StyleEditorPanel> {
  String _filter = '';
  CodeEditingController? _editor;
  String _editorKey = '';
  final FocusNode _editorFocus = FocusNode(debugLabel: 'style sheet');

  StyleEditorController get styles => widget.session.styleEditor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _selectFirst());
    styles.addListener(_selectFirst);
  }

  void _selectFirst() {
    if (!mounted || styles.selected != null || styles.sheets.isEmpty) return;
    styles.select(styles.sheets.first);
  }

  @override
  void dispose() {
    styles.removeListener(_selectFirst);
    _editor?.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  /// A controller for the sheet shown, made again when its text is replaced
  /// by something other than the typing.
  CodeEditingController _controllerFor(StyleSheetInfo sheet) {
    final key = '${sheet.resourceId}#${sheet.originalText.hashCode}';
    if (_editor == null || _editorKey != key) {
      final old = _editor;
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      _editorKey = key;
      var text = sheet.text!;
      if (looksMinified(text)) text = prettyPrintCss(text).text;
      _editor = CodeEditingController(text: text, language: SyntaxLanguage.css);
    }
    return _editor!;
  }

  int _revealed = 0;

  void _goToRequestedLine(CodeEditingController controller) {
    final request = styles.revealLine;
    if (request == null || request.$2 == _revealed) return;
    _revealed = request.$2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lines = controller.text.split('\n');
      var offset = 0;
      for (var i = 0; i < request.$1 - 1 && i < lines.length; i++) {
        offset += lines[i].length + 1;
      }
      controller.selection = TextSelection.collapsed(offset: offset.clamp(0, controller.text.length));
      _editorFocus.requestFocus();
    });
  }

  void _prettyPrint(StyleSheetInfo sheet) {
    final editor = _editor;
    if (editor == null) return;
    final text = prettyPrintCss(editor.text).text;
    editor.text = text;
    styles.edit(sheet, text);
  }

  Future<void> _importFile() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await styles.createSheet(data?.text ?? '');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: styles,
    builder: (context, _) => ColoredBox(
      color: context.dt.body,
      child: DtSplit(
        sizeSecond: false,
        initialSize: 240,
        minSize: 150,
        minOther: 260,
        settings: widget.session.settings,
        settingKey: 'styleeditor.sidebarWidth',
        first: _sidebar(context),
        second: _body(context),
      ),
    ),
  );

  Widget _sidebar(BuildContext context) {
    final colors = context.dt;
    final needle = _filter.toLowerCase();
    final sheets = styles.sheets.where((s) => s.name.toLowerCase().contains(needle)).toList();
    return Column(
      children: [
        DtToolbar(
          height: 26,
          children: [
            DtIconButton(DtGlyph.plus, iconSize: 12, tooltip: 'Create and append a new style sheet to the document', onPressed: () => styles.createSheet()),
            DtIconButton(DtGlyph.importFile, iconSize: 13, tooltip: 'Create a style sheet from the clipboard', onPressed: _importFile),
            const SizedBox(width: 4),
            Expanded(
              child: DtSearchBox(value: _filter, placeholder: 'Filter style sheets', height: 19, onChanged: (v) => setState(() => _filter = v)),
            ),
          ],
        ),
        Expanded(
          child: sheets.isEmpty
              ? const DtEmptyState('This page has no style sheets.')
              : ListView.builder(
                  itemCount: sheets.length,
                  itemBuilder: (context, index) {
                    final sheet = sheets[index];
                    final selected = styles.selected == sheet;
                    final foreground = selected ? colors.selectionText : colors.textStrong;
                    final dim = selected ? colors.selectionText : colors.textDim;
                    return DtHover(
                      onTap: () => styles.select(sheet),
                      onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, [
                        DtMenuItem('Copy URL', enabled: sheet.href.isNotEmpty, onSelected: () => Clipboard.setData(ClipboardData(text: sheet.href))),
                        DtMenuItem('Open Link in New Tab', enabled: sheet.href.isNotEmpty, onSelected: () => widget.session.onOpenLink?.call(sheet.href)),
                      ]),
                      builder: (context, hovered) => Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: selected ? colors.selection : hovered ? colors.rowHover : null,
                          border: Border(bottom: BorderSide(color: colors.splitter)),
                        ),
                        child: Row(
                          children: [
                            DtIconButton(
                              sheet.disabled ? DtGlyph.eyeOff : DtGlyph.eye,
                              width: 28,
                              iconSize: 14,
                              color: dim,
                              tooltip: 'Toggle style sheet visibility',
                              onPressed: () => styles.setDisabled(sheet, !sheet.disabled),
                            ),
                            Expanded(
                              child: Opacity(
                                opacity: sheet.disabled ? 0.55 : 1,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${sheet.isModified ? '*' : ''}${sheet.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.uiStyle(color: foreground, weight: FontWeight.w600),
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text('${sheet.ruleCount} rules.', style: context.uiStyle(color: dim, size: 11)),
                                        ),
                                        DtHover(
                                          cursor: SystemMouseCursors.click,
                                          onTap: () => styles.save(sheet),
                                          builder: (context, hovered) => Text(
                                            'Save',
                                            style: context.uiStyle(color: selected ? colors.selectionText : colors.accent, size: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// The at-rules of the sheet shown, with the lines they start on.
  static List<(String, int)> _atRules(String text) {
    final rules = <(String, int)>[];
    final lines = text.split('\n');
    final pattern = RegExp(r'@(media|supports|container|layer)\b([^{;]*)\{');
    for (final (index, line) in lines.indexed) {
      for (final match in pattern.allMatches(line)) {
        rules.add(('@${match.group(1)} ${match.group(2)!.trim()}', index + 1));
      }
    }
    return rules;
  }

  Widget _body(BuildContext context) {
    final colors = context.dt;
    final sheet = styles.selected;
    if (sheet == null) {
      return const DtEmptyState('Select a style sheet to edit it.');
    }
    if (sheet.text == null) {
      return DtEmptyState(sheet.error.isEmpty ? 'Loading…' : sheet.error);
    }
    final controller = _controllerFor(sheet);
    _goToRequestedLine(controller);
    final atRules = _atRules(controller.text);
    return Column(
      children: [
        DtToolbar(
          height: 26,
          children: [
            Expanded(
              child: Text(
                sheet.href.isEmpty ? sheet.name : sheet.href,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.uiStyle(color: colors.textDim, size: 11),
              ),
            ),
            DtIconButton(DtGlyph.prettyPrint, iconSize: 15, tooltip: 'Pretty print', onPressed: () => _prettyPrint(sheet)),
            DtIconButton(DtGlyph.copy, iconSize: 13, tooltip: 'Copy style sheet', onPressed: () => Clipboard.setData(ClipboardData(text: controller.text))),
            DtIconButton(
              DtGlyph.reload,
              iconSize: 12,
              tooltip: 'Revert to the page’s own text',
              onPressed: !sheet.isModified
                  ? null
                  : () {
                      controller.text = sheet.originalText ?? '';
                      styles.edit(sheet, controller.text);
                    },
            ),
          ],
        ),
        if (sheet.error.isNotEmpty)
          Container(
            width: double.infinity,
            color: colors.errorBackground,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(sheet.error, style: context.uiStyle(color: colors.errorText, size: 11)),
          ),
        Expanded(
          child: DtSplit(
            initialSize: 190,
            minSize: 100,
            minOther: 200,
            showSecond: atRules.isNotEmpty,
            first: DtCodeEditor(
              key: ValueKey(_editorKey),
              controller: controller,
              focusNode: _editorFocus,
              onChanged: (text) => styles.edit(sheet, text),
              onKey: (event) {
                final command = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
                if (event is KeyDownEvent && command && event.logicalKey == LogicalKeyboardKey.keyS) {
                  styles.save(sheet);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
            ),
            second: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 22,
                  color: colors.toolbar,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  child: Text('At-rules', style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final (rule, line) in atRules)
                        DtHover(
                          onTap: () {
                            var offset = 0;
                            final lines = controller.text.split('\n');
                            for (var i = 0; i < line - 1 && i < lines.length; i++) {
                              offset += lines[i].length + 1;
                            }
                            controller.selection = TextSelection.collapsed(offset: offset);
                            _editorFocus.requestFocus();
                          },
                          builder: (context, hovered) => Container(
                            color: hovered ? colors.rowHover : null,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: rule),
                                  TextSpan(text: '  :$line', style: TextStyle(color: colors.textDim)),
                                ],
                              ),
                              style: context.monoStyle(color: colors.textStrong),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

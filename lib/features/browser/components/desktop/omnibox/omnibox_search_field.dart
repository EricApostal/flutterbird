import 'package:bird_session/bird_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_suggestions_overlay.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_url_text.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/picture_in_picture_button.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/site_info_button.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';
import 'package:ladybird/ladybird.dart';

/// The URL/search input in the desktop omnibox toolbar, with the suggestions
/// that open beneath it and the address it fills in as the user types.
/// Navigation is fully delegated to the parent via [onSubmitted] and
/// [onSuggestionSelected] since the parent owns the per-tab text-sync state
/// that a committed navigation needs to update.
class OmniboxSearchField extends StatefulWidget {
  final LadybirdController currentTabController;
  final TextEditingController omniBoxTextController;
  final FocusNode omniboxFocusNode;
  final BrowserOmnibox omniboxController;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<OmniboxSuggestion> onSuggestionSelected;

  const OmniboxSearchField({
    super.key,
    required this.currentTabController,
    required this.omniBoxTextController,
    required this.omniboxFocusNode,
    required this.omniboxController,
    required this.onSubmitted,
    required this.onSuggestionSelected,
  });

  @override
  State<OmniboxSearchField> createState() => _OmniboxSearchFieldState();
}

class _OmniboxSearchFieldState extends State<OmniboxSearchField> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();
  double _width = 0;

  /// What the user has typed, which is not all of what the field shows while
  /// an address is filled in after it.
  String _typed = '';
  OmniboxProposal _proposal = const OmniboxProposal([], null);
  int _selected = 0;
  bool _hadFocus = false;

  TextEditingController get _text => widget.omniBoxTextController;
  FocusNode get _focus => widget.omniboxFocusNode;
  bool get _isOpen => _overlay.isShowing;

  @override
  void initState() {
    super.initState();
    _hadFocus = _focus.hasFocus;
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(OmniboxSearchField old) {
    super.didUpdateWidget(old);
    if (old.omniboxFocusNode != widget.omniboxFocusNode) {
      old.omniboxFocusNode.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
    if (old.currentTabController.viewId != widget.currentTabController.viewId) {
      // Another tab's suggestions are about what was typed in that one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    super.dispose();
  }

  void _focusChanged() {
    // The node also reports while it keeps the focus, when what is filled in
    // must not be taken for something typed.
    if (!mounted || _focus.hasFocus == _hadFocus) return;
    _hadFocus = _focus.hasFocus;
    if (_hadFocus) {
      _typed = _text.text;
    } else {
      _close();
    }
    setState(() {});
  }

  void _close() {
    if (_overlay.isShowing) _overlay.hide();
    _proposal = const OmniboxProposal([], null);
    _selected = 0;
    if (mounted) setState(() {});
  }

  /// Asks for suggestions for what is typed, and opens or closes on them.
  void _suggest({required bool complete}) {
    _proposal = widget.omniboxController.propose(
      widget.currentTabController,
      _typed,
      complete: complete,
    );
    _selected = 0;
    if (_proposal.rows.isEmpty) {
      if (_overlay.isShowing) _overlay.hide();
    } else if (!_overlay.isShowing) {
      _overlay.show();
    }
    setState(() {});
  }

  /// Runs on the user's edits only; setting the field's text does not.
  void _edited(String _) {
    final value = _text.value;
    final complete = allowsInlineCompletion(
      previous: _typed,
      typed: value.text,
      caretAtEnd:
          value.selection.isCollapsed &&
          value.selection.end == value.text.length,
      composing: value.composing.isValid && !value.composing.isCollapsed,
    );
    _typed = value.text;
    _suggest(complete: complete);
    _fillCompletion();
  }

  /// Puts the rest of the proposed address after what was typed, selected, so
  /// that typing on replaces it.
  void _fillCompletion() {
    final completion = _proposal.completion;
    if (completion == null) return;
    _text.value = TextEditingValue(
      text: completion.text,
      selection: TextSelection(
        baseOffset: _typed.length,
        extentOffset: completion.text.length,
      ),
    );
  }

  void _showText(String text) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Moves through the suggestions, showing in the field where each one goes.
  void _move(int step) {
    final rows = _proposal.rows;
    if (rows.isEmpty) return;
    setState(() => _selected = (_selected + step) % rows.length);

    if (_selected == 0) {
      _showText(_typed);
      _fillCompletion();
      return;
    }
    final row = rows[_selected];
    _showText(row.isSearch ? row.value : displayAddress(row.value));
  }

  void _choose(OmniboxSuggestion row) {
    _close();
    widget.onSuggestionSelected(row);
  }

  void _submit(String value) {
    final rows = _proposal.rows;
    // What is in the field says where to go, unless a suggestion was picked
    // out, or the field holds the address this filled in, whose real form is
    // longer than what it shows.
    if (_isOpen && _selected > 0 && _selected < rows.length) {
      _choose(rows[_selected]);
      return;
    }
    final completion = _isOpen ? _proposal.completion : null;
    _close();
    if (completion != null && value == completion.text) {
      widget.onSuggestionSelected(rows.first);
    } else {
      widget.onSubmitted(value);
    }
  }

  void _forget(OmniboxSuggestion row) {
    if (!removeHistoryEntry(row.value)) return;
    _showText(_typed);
    _suggest(complete: false);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // An input method composing a word has its own use for these.
    if (_text.value.composing.isValid && !_text.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (_isOpen) {
        _move(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _typed = _text.text;
        _suggest(complete: false);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_isOpen && _selected != 0) {
        // Back to what was typed first, then away.
        _move(-_selected);
        return KeyEventResult.handled;
      }
      if (_isOpen) {
        _showText(_typed);
        _close();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.delete &&
        HardwareKeyboard.instance.isShiftPressed &&
        _isOpen &&
        _selected < _proposal.rows.length &&
        _proposal.rows[_selected].type == OmniboxSuggestionType.history) {
      _forget(_proposal.rows[_selected]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildOverlayText(ThemeData theme, String text) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          // Clear of the buttons at either end of the field.
          padding: const EdgeInsets.only(
            left: kSiteInfoButtonWidth,
            right: kPictureInPictureButtonWidth,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
              styledUrlSpan(theme, text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: StrutStyle.fromTextStyle(theme.textTheme.bodyMedium!),
            ),
          ),
        ),
      ),
    );
  }

  /// The field's shape and fill. It has no outline: open, it is the top of the
  /// panel, so its lower corners are square where the suggestions carry on.
  InputBorder _border(bool open) {
    const top = Radius.circular(kOmniboxPanelRadius);
    return OutlineInputBorder(
      borderRadius: open
          ? const BorderRadius.vertical(top: top)
          : BorderRadius.circular(kOmniboxFieldRadius),
      borderSide: BorderSide.none,
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return Positioned(
      width: _width,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        showWhenUnlinked: false,
        // A press on a suggestion is a press on the field, which must not lose
        // the keyboard to it.
        child: TextFieldTapRegion(
          child: OmniboxSuggestionsOverlay(
            options: _proposal.rows,
            query: _typed,
            selected: _selected,
            onSelected: _choose,
            onRemove: _forget,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<String>(
      valueListenable: widget.currentTabController.urlNotifier,
      builder: (context, url, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            return CompositedTransformTarget(
              link: _link,
              child: OverlayPortal(
                controller: _overlay,
                overlayChildBuilder: _buildSuggestions,
                child: _buildField(context, theme),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildField(BuildContext context, ThemeData theme) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _text,
      builder: (context, editingValue, child) {
        final isFocused = _focus.hasFocus;
        final border = _border(_isOpen);

        return Stack(
          children: [
            Focus(
              // Only to hear the keys the field itself has no use for.
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _key,
              child: TextField(
                onChanged: _edited,
                onSubmitted: _submit,
                controller: _text,
                focusNode: _focus,
                autocorrect: false,
                enableSuggestions: false,
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontSize: 13,
                  color: isFocused
                      ? theme.colorScheme.onSurface
                      : Colors.transparent,
                ),
                decoration: InputDecoration(
                  prefixIcon: SiteInfoButton(tab: widget.currentTabController),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: kSiteInfoButtonWidth,
                    maxWidth: kSiteInfoButtonWidth,
                    minHeight: 30,
                  ),
                  suffixIcon: PictureInPictureButton(
                    tab: widget.currentTabController,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minHeight: 30,
                    maxWidth: kPictureInPictureButtonWidth,
                  ),
                  filled: true,
                  fillColor: omniboxSurfaceColor(theme),
                  hoverColor: Colors.transparent,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  hintText:
                      'Search ${widget.omniboxController.searchEngineLabel(widget.currentTabController)} or type a URL',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border,
                ),
              ),
            ),
            if (!isFocused) _buildOverlayText(theme, editingValue.text),
          ],
        );
      },
    );
  }
}

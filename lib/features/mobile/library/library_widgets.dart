import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

/// A screen with a list of the browser's own: history, bookmarks, downloads or
/// closed tabs. With [onSearch], the bar can turn into a search box.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.title,
    required this.child,
    this.onSearch,
    this.actions = const [],
    super.key,
  });

  final String title;
  final Widget child;
  final ValueChanged<String>? onSearch;
  final List<Widget> actions;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _query = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _stopSearching() {
    _query.clear();
    widget.onSearch?.call('');
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _stopSearching();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          shape: Border(bottom: BorderSide(color: colors.divider, width: 0.6)),
          leading: BackButton(
            onPressed: _searching
                ? _stopSearching
                : () => Navigator.of(context).pop(),
          ),
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: _searching
                ? TextField(
                    key: const ValueKey('search'),
                    controller: _query,
                    autofocus: true,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Search',
                    ),
                    onChanged: widget.onSearch,
                  )
                : Text(widget.title, key: const ValueKey('title')),
          ),
          actions: [
            if (widget.onSearch != null && !_searching)
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _searching = true),
              ),
            if (_searching)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _query.clear();
                  widget.onSearch?.call('');
                },
              ),
            if (!_searching) ...widget.actions,
          ],
        ),
        body: SafeArea(top: false, child: widget.child),
      ),
    );
  }
}

class LibraryRow extends StatelessWidget {
  const LibraryRow({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.onLongPress,
    this.below,
    super.key,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Such as a download's progress.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.container,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: leading,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: colors.text),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    if (below != null) ...[const SizedBox(height: 8), below!],
                  ],
                ),
              ),
              trailing ?? const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryEmpty extends StatelessWidget {
  const LibraryEmpty({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

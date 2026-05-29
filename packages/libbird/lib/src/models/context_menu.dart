import 'package:dart_mappable/dart_mappable.dart';

part 'context_menu.mapper.dart';

@MappableClass()
class LadybirdContextMenuEntry with LadybirdContextMenuEntryMappable {
  const LadybirdContextMenuEntry({
    this.kind = 'action',
    this.text = '',
    @MappableField(key: 'token') this.actionToken,
    this.enabled = true,
    this.checkable = false,
    this.checked = false,
    this.items = const [],
  });

  final String kind;
  final String text;
  final int? actionToken;
  final bool enabled;
  final bool checkable;
  final bool checked;
  final List<LadybirdContextMenuEntry> items;

  bool get isAction => kind == 'action';
  bool get isSeparator => kind == 'separator';
  bool get isSubmenu => kind == 'submenu';
}

@MappableClass()
class LadybirdContextMenuRequest with LadybirdContextMenuRequestMappable {
  const LadybirdContextMenuRequest({
    this.type = 'page',
    this.x = 0,
    this.y = 0,
    this.items = const [],
  });

  final String type;
  final int x;
  final int y;
  final List<LadybirdContextMenuEntry> items;
}

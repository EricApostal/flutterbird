// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'context_menu.dart';

class LadybirdContextMenuEntryMapper
    extends ClassMapperBase<LadybirdContextMenuEntry> {
  LadybirdContextMenuEntryMapper._();

  static LadybirdContextMenuEntryMapper? _instance;
  static LadybirdContextMenuEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = LadybirdContextMenuEntryMapper._(),
      );
      LadybirdContextMenuEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LadybirdContextMenuEntry';

  static String _$kind(LadybirdContextMenuEntry v) => v.kind;
  static const Field<LadybirdContextMenuEntry, String> _f$kind = Field(
    'kind',
    _$kind,
    opt: true,
    def: 'action',
  );
  static String _$text(LadybirdContextMenuEntry v) => v.text;
  static const Field<LadybirdContextMenuEntry, String> _f$text = Field(
    'text',
    _$text,
    opt: true,
    def: '',
  );
  static int? _$actionToken(LadybirdContextMenuEntry v) => v.actionToken;
  static const Field<LadybirdContextMenuEntry, int> _f$actionToken = Field(
    'actionToken',
    _$actionToken,
    key: r'token',
    opt: true,
  );
  static bool _$enabled(LadybirdContextMenuEntry v) => v.enabled;
  static const Field<LadybirdContextMenuEntry, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static bool _$checkable(LadybirdContextMenuEntry v) => v.checkable;
  static const Field<LadybirdContextMenuEntry, bool> _f$checkable = Field(
    'checkable',
    _$checkable,
    opt: true,
    def: false,
  );
  static bool _$checked(LadybirdContextMenuEntry v) => v.checked;
  static const Field<LadybirdContextMenuEntry, bool> _f$checked = Field(
    'checked',
    _$checked,
    opt: true,
    def: false,
  );
  static List<LadybirdContextMenuEntry> _$items(LadybirdContextMenuEntry v) =>
      v.items;
  static const Field<LadybirdContextMenuEntry, List<LadybirdContextMenuEntry>>
  _f$items = Field('items', _$items, opt: true, def: const []);

  @override
  final MappableFields<LadybirdContextMenuEntry> fields = const {
    #kind: _f$kind,
    #text: _f$text,
    #actionToken: _f$actionToken,
    #enabled: _f$enabled,
    #checkable: _f$checkable,
    #checked: _f$checked,
    #items: _f$items,
  };

  static LadybirdContextMenuEntry _instantiate(DecodingData data) {
    return LadybirdContextMenuEntry(
      kind: data.dec(_f$kind),
      text: data.dec(_f$text),
      actionToken: data.dec(_f$actionToken),
      enabled: data.dec(_f$enabled),
      checkable: data.dec(_f$checkable),
      checked: data.dec(_f$checked),
      items: data.dec(_f$items),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LadybirdContextMenuEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LadybirdContextMenuEntry>(map);
  }

  static LadybirdContextMenuEntry fromJson(String json) {
    return ensureInitialized().decodeJson<LadybirdContextMenuEntry>(json);
  }
}

mixin LadybirdContextMenuEntryMappable {
  String toJson() {
    return LadybirdContextMenuEntryMapper.ensureInitialized()
        .encodeJson<LadybirdContextMenuEntry>(this as LadybirdContextMenuEntry);
  }

  Map<String, dynamic> toMap() {
    return LadybirdContextMenuEntryMapper.ensureInitialized()
        .encodeMap<LadybirdContextMenuEntry>(this as LadybirdContextMenuEntry);
  }

  LadybirdContextMenuEntryCopyWith<
    LadybirdContextMenuEntry,
    LadybirdContextMenuEntry,
    LadybirdContextMenuEntry
  >
  get copyWith =>
      _LadybirdContextMenuEntryCopyWithImpl<
        LadybirdContextMenuEntry,
        LadybirdContextMenuEntry
      >(this as LadybirdContextMenuEntry, $identity, $identity);
  @override
  String toString() {
    return LadybirdContextMenuEntryMapper.ensureInitialized().stringifyValue(
      this as LadybirdContextMenuEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return LadybirdContextMenuEntryMapper.ensureInitialized().equalsValue(
      this as LadybirdContextMenuEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return LadybirdContextMenuEntryMapper.ensureInitialized().hashValue(
      this as LadybirdContextMenuEntry,
    );
  }
}

extension LadybirdContextMenuEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LadybirdContextMenuEntry, $Out> {
  LadybirdContextMenuEntryCopyWith<$R, LadybirdContextMenuEntry, $Out>
  get $asLadybirdContextMenuEntry => $base.as(
    (v, t, t2) => _LadybirdContextMenuEntryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LadybirdContextMenuEntryCopyWith<
  $R,
  $In extends LadybirdContextMenuEntry,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    LadybirdContextMenuEntry,
    LadybirdContextMenuEntryCopyWith<
      $R,
      LadybirdContextMenuEntry,
      LadybirdContextMenuEntry
    >
  >
  get items;
  $R call({
    String? kind,
    String? text,
    int? actionToken,
    bool? enabled,
    bool? checkable,
    bool? checked,
    List<LadybirdContextMenuEntry>? items,
  });
  LadybirdContextMenuEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LadybirdContextMenuEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LadybirdContextMenuEntry, $Out>
    implements
        LadybirdContextMenuEntryCopyWith<$R, LadybirdContextMenuEntry, $Out> {
  _LadybirdContextMenuEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LadybirdContextMenuEntry> $mapper =
      LadybirdContextMenuEntryMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    LadybirdContextMenuEntry,
    LadybirdContextMenuEntryCopyWith<
      $R,
      LadybirdContextMenuEntry,
      LadybirdContextMenuEntry
    >
  >
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  $R call({
    String? kind,
    String? text,
    Object? actionToken = $none,
    bool? enabled,
    bool? checkable,
    bool? checked,
    List<LadybirdContextMenuEntry>? items,
  }) => $apply(
    FieldCopyWithData({
      if (kind != null) #kind: kind,
      if (text != null) #text: text,
      if (actionToken != $none) #actionToken: actionToken,
      if (enabled != null) #enabled: enabled,
      if (checkable != null) #checkable: checkable,
      if (checked != null) #checked: checked,
      if (items != null) #items: items,
    }),
  );
  @override
  LadybirdContextMenuEntry $make(CopyWithData data) => LadybirdContextMenuEntry(
    kind: data.get(#kind, or: $value.kind),
    text: data.get(#text, or: $value.text),
    actionToken: data.get(#actionToken, or: $value.actionToken),
    enabled: data.get(#enabled, or: $value.enabled),
    checkable: data.get(#checkable, or: $value.checkable),
    checked: data.get(#checked, or: $value.checked),
    items: data.get(#items, or: $value.items),
  );

  @override
  LadybirdContextMenuEntryCopyWith<$R2, LadybirdContextMenuEntry, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LadybirdContextMenuEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LadybirdContextMenuRequestMapper
    extends ClassMapperBase<LadybirdContextMenuRequest> {
  LadybirdContextMenuRequestMapper._();

  static LadybirdContextMenuRequestMapper? _instance;
  static LadybirdContextMenuRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = LadybirdContextMenuRequestMapper._(),
      );
      LadybirdContextMenuEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LadybirdContextMenuRequest';

  static String _$type(LadybirdContextMenuRequest v) => v.type;
  static const Field<LadybirdContextMenuRequest, String> _f$type = Field(
    'type',
    _$type,
    opt: true,
    def: 'page',
  );
  static int _$x(LadybirdContextMenuRequest v) => v.x;
  static const Field<LadybirdContextMenuRequest, int> _f$x = Field(
    'x',
    _$x,
    opt: true,
    def: 0,
  );
  static int _$y(LadybirdContextMenuRequest v) => v.y;
  static const Field<LadybirdContextMenuRequest, int> _f$y = Field(
    'y',
    _$y,
    opt: true,
    def: 0,
  );
  static List<LadybirdContextMenuEntry> _$items(LadybirdContextMenuRequest v) =>
      v.items;
  static const Field<LadybirdContextMenuRequest, List<LadybirdContextMenuEntry>>
  _f$items = Field('items', _$items, opt: true, def: const []);

  @override
  final MappableFields<LadybirdContextMenuRequest> fields = const {
    #type: _f$type,
    #x: _f$x,
    #y: _f$y,
    #items: _f$items,
  };

  static LadybirdContextMenuRequest _instantiate(DecodingData data) {
    return LadybirdContextMenuRequest(
      type: data.dec(_f$type),
      x: data.dec(_f$x),
      y: data.dec(_f$y),
      items: data.dec(_f$items),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LadybirdContextMenuRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LadybirdContextMenuRequest>(map);
  }

  static LadybirdContextMenuRequest fromJson(String json) {
    return ensureInitialized().decodeJson<LadybirdContextMenuRequest>(json);
  }
}

mixin LadybirdContextMenuRequestMappable {
  String toJson() {
    return LadybirdContextMenuRequestMapper.ensureInitialized()
        .encodeJson<LadybirdContextMenuRequest>(
          this as LadybirdContextMenuRequest,
        );
  }

  Map<String, dynamic> toMap() {
    return LadybirdContextMenuRequestMapper.ensureInitialized()
        .encodeMap<LadybirdContextMenuRequest>(
          this as LadybirdContextMenuRequest,
        );
  }

  LadybirdContextMenuRequestCopyWith<
    LadybirdContextMenuRequest,
    LadybirdContextMenuRequest,
    LadybirdContextMenuRequest
  >
  get copyWith =>
      _LadybirdContextMenuRequestCopyWithImpl<
        LadybirdContextMenuRequest,
        LadybirdContextMenuRequest
      >(this as LadybirdContextMenuRequest, $identity, $identity);
  @override
  String toString() {
    return LadybirdContextMenuRequestMapper.ensureInitialized().stringifyValue(
      this as LadybirdContextMenuRequest,
    );
  }

  @override
  bool operator ==(Object other) {
    return LadybirdContextMenuRequestMapper.ensureInitialized().equalsValue(
      this as LadybirdContextMenuRequest,
      other,
    );
  }

  @override
  int get hashCode {
    return LadybirdContextMenuRequestMapper.ensureInitialized().hashValue(
      this as LadybirdContextMenuRequest,
    );
  }
}

extension LadybirdContextMenuRequestValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LadybirdContextMenuRequest, $Out> {
  LadybirdContextMenuRequestCopyWith<$R, LadybirdContextMenuRequest, $Out>
  get $asLadybirdContextMenuRequest => $base.as(
    (v, t, t2) => _LadybirdContextMenuRequestCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LadybirdContextMenuRequestCopyWith<
  $R,
  $In extends LadybirdContextMenuRequest,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    LadybirdContextMenuEntry,
    LadybirdContextMenuEntryCopyWith<
      $R,
      LadybirdContextMenuEntry,
      LadybirdContextMenuEntry
    >
  >
  get items;
  $R call({
    String? type,
    int? x,
    int? y,
    List<LadybirdContextMenuEntry>? items,
  });
  LadybirdContextMenuRequestCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LadybirdContextMenuRequestCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LadybirdContextMenuRequest, $Out>
    implements
        LadybirdContextMenuRequestCopyWith<
          $R,
          LadybirdContextMenuRequest,
          $Out
        > {
  _LadybirdContextMenuRequestCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LadybirdContextMenuRequest> $mapper =
      LadybirdContextMenuRequestMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    LadybirdContextMenuEntry,
    LadybirdContextMenuEntryCopyWith<
      $R,
      LadybirdContextMenuEntry,
      LadybirdContextMenuEntry
    >
  >
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  $R call({
    String? type,
    int? x,
    int? y,
    List<LadybirdContextMenuEntry>? items,
  }) => $apply(
    FieldCopyWithData({
      if (type != null) #type: type,
      if (x != null) #x: x,
      if (y != null) #y: y,
      if (items != null) #items: items,
    }),
  );
  @override
  LadybirdContextMenuRequest $make(CopyWithData data) =>
      LadybirdContextMenuRequest(
        type: data.get(#type, or: $value.type),
        x: data.get(#x, or: $value.x),
        y: data.get(#y, or: $value.y),
        items: data.get(#items, or: $value.items),
      );

  @override
  LadybirdContextMenuRequestCopyWith<$R2, LadybirdContextMenuRequest, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LadybirdContextMenuRequestCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


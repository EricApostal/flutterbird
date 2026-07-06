// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'settings.dart';

class LadybirdSearchEngineMapper extends ClassMapperBase<LadybirdSearchEngine> {
  LadybirdSearchEngineMapper._();

  static LadybirdSearchEngineMapper? _instance;
  static LadybirdSearchEngineMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LadybirdSearchEngineMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'LadybirdSearchEngine';

  static String _$name(LadybirdSearchEngine v) => v.name;
  static const Field<LadybirdSearchEngine, String> _f$name = Field(
    'name',
    _$name,
  );
  static String _$queryUrl(LadybirdSearchEngine v) => v.queryUrl;
  static const Field<LadybirdSearchEngine, String> _f$queryUrl = Field(
    'queryUrl',
    _$queryUrl,
  );

  @override
  final MappableFields<LadybirdSearchEngine> fields = const {
    #name: _f$name,
    #queryUrl: _f$queryUrl,
  };

  static LadybirdSearchEngine _instantiate(DecodingData data) {
    return LadybirdSearchEngine(
      name: data.dec(_f$name),
      queryUrl: data.dec(_f$queryUrl),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LadybirdSearchEngine fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LadybirdSearchEngine>(map);
  }

  static LadybirdSearchEngine fromJson(String json) {
    return ensureInitialized().decodeJson<LadybirdSearchEngine>(json);
  }
}

mixin LadybirdSearchEngineMappable {
  String toJson() {
    return LadybirdSearchEngineMapper.ensureInitialized()
        .encodeJson<LadybirdSearchEngine>(this as LadybirdSearchEngine);
  }

  Map<String, dynamic> toMap() {
    return LadybirdSearchEngineMapper.ensureInitialized()
        .encodeMap<LadybirdSearchEngine>(this as LadybirdSearchEngine);
  }

  LadybirdSearchEngineCopyWith<
    LadybirdSearchEngine,
    LadybirdSearchEngine,
    LadybirdSearchEngine
  >
  get copyWith =>
      _LadybirdSearchEngineCopyWithImpl<
        LadybirdSearchEngine,
        LadybirdSearchEngine
      >(this as LadybirdSearchEngine, $identity, $identity);
  @override
  String toString() {
    return LadybirdSearchEngineMapper.ensureInitialized().stringifyValue(
      this as LadybirdSearchEngine,
    );
  }

  @override
  bool operator ==(Object other) {
    return LadybirdSearchEngineMapper.ensureInitialized().equalsValue(
      this as LadybirdSearchEngine,
      other,
    );
  }

  @override
  int get hashCode {
    return LadybirdSearchEngineMapper.ensureInitialized().hashValue(
      this as LadybirdSearchEngine,
    );
  }
}

extension LadybirdSearchEngineValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LadybirdSearchEngine, $Out> {
  LadybirdSearchEngineCopyWith<$R, LadybirdSearchEngine, $Out>
  get $asLadybirdSearchEngine => $base.as(
    (v, t, t2) => _LadybirdSearchEngineCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LadybirdSearchEngineCopyWith<
  $R,
  $In extends LadybirdSearchEngine,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? name, String? queryUrl});
  LadybirdSearchEngineCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LadybirdSearchEngineCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LadybirdSearchEngine, $Out>
    implements LadybirdSearchEngineCopyWith<$R, LadybirdSearchEngine, $Out> {
  _LadybirdSearchEngineCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LadybirdSearchEngine> $mapper =
      LadybirdSearchEngineMapper.ensureInitialized();
  @override
  $R call({String? name, String? queryUrl}) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (queryUrl != null) #queryUrl: queryUrl,
    }),
  );
  @override
  LadybirdSearchEngine $make(CopyWithData data) => LadybirdSearchEngine(
    name: data.get(#name, or: $value.name),
    queryUrl: data.get(#queryUrl, or: $value.queryUrl),
  );

  @override
  LadybirdSearchEngineCopyWith<$R2, LadybirdSearchEngine, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LadybirdSearchEngineCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LadybirdConfigVariableDefinitionMapper
    extends ClassMapperBase<LadybirdConfigVariableDefinition> {
  LadybirdConfigVariableDefinitionMapper._();

  static LadybirdConfigVariableDefinitionMapper? _instance;
  static LadybirdConfigVariableDefinitionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = LadybirdConfigVariableDefinitionMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'LadybirdConfigVariableDefinition';

  static String _$name(LadybirdConfigVariableDefinition v) => v.name;
  static const Field<LadybirdConfigVariableDefinition, String> _f$name = Field(
    'name',
    _$name,
  );
  static String _$title(LadybirdConfigVariableDefinition v) => v.title;
  static const Field<LadybirdConfigVariableDefinition, String> _f$title = Field(
    'title',
    _$title,
  );
  static String _$description(LadybirdConfigVariableDefinition v) =>
      v.description;
  static const Field<LadybirdConfigVariableDefinition, String> _f$description =
      Field('description', _$description);
  static dynamic _$defaultValue(LadybirdConfigVariableDefinition v) =>
      v.defaultValue;
  static const Field<LadybirdConfigVariableDefinition, dynamic>
  _f$defaultValue = Field('defaultValue', _$defaultValue);
  static String? _$arrayElementType(LadybirdConfigVariableDefinition v) =>
      v.arrayElementType;
  static const Field<LadybirdConfigVariableDefinition, String>
  _f$arrayElementType = Field(
    'arrayElementType',
    _$arrayElementType,
    opt: true,
  );

  @override
  final MappableFields<LadybirdConfigVariableDefinition> fields = const {
    #name: _f$name,
    #title: _f$title,
    #description: _f$description,
    #defaultValue: _f$defaultValue,
    #arrayElementType: _f$arrayElementType,
  };

  static LadybirdConfigVariableDefinition _instantiate(DecodingData data) {
    return LadybirdConfigVariableDefinition(
      name: data.dec(_f$name),
      title: data.dec(_f$title),
      description: data.dec(_f$description),
      defaultValue: data.dec(_f$defaultValue),
      arrayElementType: data.dec(_f$arrayElementType),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LadybirdConfigVariableDefinition fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LadybirdConfigVariableDefinition>(map);
  }

  static LadybirdConfigVariableDefinition fromJson(String json) {
    return ensureInitialized().decodeJson<LadybirdConfigVariableDefinition>(
      json,
    );
  }
}

mixin LadybirdConfigVariableDefinitionMappable {
  String toJson() {
    return LadybirdConfigVariableDefinitionMapper.ensureInitialized()
        .encodeJson<LadybirdConfigVariableDefinition>(
          this as LadybirdConfigVariableDefinition,
        );
  }

  Map<String, dynamic> toMap() {
    return LadybirdConfigVariableDefinitionMapper.ensureInitialized()
        .encodeMap<LadybirdConfigVariableDefinition>(
          this as LadybirdConfigVariableDefinition,
        );
  }

  LadybirdConfigVariableDefinitionCopyWith<
    LadybirdConfigVariableDefinition,
    LadybirdConfigVariableDefinition,
    LadybirdConfigVariableDefinition
  >
  get copyWith =>
      _LadybirdConfigVariableDefinitionCopyWithImpl<
        LadybirdConfigVariableDefinition,
        LadybirdConfigVariableDefinition
      >(this as LadybirdConfigVariableDefinition, $identity, $identity);
  @override
  String toString() {
    return LadybirdConfigVariableDefinitionMapper.ensureInitialized()
        .stringifyValue(this as LadybirdConfigVariableDefinition);
  }

  @override
  bool operator ==(Object other) {
    return LadybirdConfigVariableDefinitionMapper.ensureInitialized()
        .equalsValue(this as LadybirdConfigVariableDefinition, other);
  }

  @override
  int get hashCode {
    return LadybirdConfigVariableDefinitionMapper.ensureInitialized().hashValue(
      this as LadybirdConfigVariableDefinition,
    );
  }
}

extension LadybirdConfigVariableDefinitionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LadybirdConfigVariableDefinition, $Out> {
  LadybirdConfigVariableDefinitionCopyWith<
    $R,
    LadybirdConfigVariableDefinition,
    $Out
  >
  get $asLadybirdConfigVariableDefinition => $base.as(
    (v, t, t2) =>
        _LadybirdConfigVariableDefinitionCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LadybirdConfigVariableDefinitionCopyWith<
  $R,
  $In extends LadybirdConfigVariableDefinition,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? name,
    String? title,
    String? description,
    dynamic defaultValue,
    String? arrayElementType,
  });
  LadybirdConfigVariableDefinitionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LadybirdConfigVariableDefinitionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LadybirdConfigVariableDefinition, $Out>
    implements
        LadybirdConfigVariableDefinitionCopyWith<
          $R,
          LadybirdConfigVariableDefinition,
          $Out
        > {
  _LadybirdConfigVariableDefinitionCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<LadybirdConfigVariableDefinition> $mapper =
      LadybirdConfigVariableDefinitionMapper.ensureInitialized();
  @override
  $R call({
    String? name,
    String? title,
    String? description,
    Object? defaultValue = $none,
    Object? arrayElementType = $none,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (title != null) #title: title,
      if (description != null) #description: description,
      if (defaultValue != $none) #defaultValue: defaultValue,
      if (arrayElementType != $none) #arrayElementType: arrayElementType,
    }),
  );
  @override
  LadybirdConfigVariableDefinition $make(CopyWithData data) =>
      LadybirdConfigVariableDefinition(
        name: data.get(#name, or: $value.name),
        title: data.get(#title, or: $value.title),
        description: data.get(#description, or: $value.description),
        defaultValue: data.get(#defaultValue, or: $value.defaultValue),
        arrayElementType: data.get(
          #arrayElementType,
          or: $value.arrayElementType,
        ),
      );

  @override
  LadybirdConfigVariableDefinitionCopyWith<
    $R2,
    LadybirdConfigVariableDefinition,
    $Out2
  >
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LadybirdConfigVariableDefinitionCopyWithImpl<$R2, $Out2>(
        $value,
        $cast,
        t,
      );
}


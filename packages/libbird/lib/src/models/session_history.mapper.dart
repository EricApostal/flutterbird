// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'session_history.dart';

class LadybirdSessionHistoryEntryMapper
    extends ClassMapperBase<LadybirdSessionHistoryEntry> {
  LadybirdSessionHistoryEntryMapper._();

  static LadybirdSessionHistoryEntryMapper? _instance;
  static LadybirdSessionHistoryEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = LadybirdSessionHistoryEntryMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'LadybirdSessionHistoryEntry';

  static int _$step(LadybirdSessionHistoryEntry v) => v.step;
  static const Field<LadybirdSessionHistoryEntry, int> _f$step = Field(
    'step',
    _$step,
  );
  static String _$url(LadybirdSessionHistoryEntry v) => v.url;
  static const Field<LadybirdSessionHistoryEntry, String> _f$url = Field(
    'url',
    _$url,
  );
  static bool _$current(LadybirdSessionHistoryEntry v) => v.current;
  static const Field<LadybirdSessionHistoryEntry, bool> _f$current = Field(
    'current',
    _$current,
  );

  @override
  final MappableFields<LadybirdSessionHistoryEntry> fields = const {
    #step: _f$step,
    #url: _f$url,
    #current: _f$current,
  };

  static LadybirdSessionHistoryEntry _instantiate(DecodingData data) {
    return LadybirdSessionHistoryEntry(
      step: data.dec(_f$step),
      url: data.dec(_f$url),
      current: data.dec(_f$current),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LadybirdSessionHistoryEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LadybirdSessionHistoryEntry>(map);
  }

  static LadybirdSessionHistoryEntry fromJson(String json) {
    return ensureInitialized().decodeJson<LadybirdSessionHistoryEntry>(json);
  }
}

mixin LadybirdSessionHistoryEntryMappable {
  String toJson() {
    return LadybirdSessionHistoryEntryMapper.ensureInitialized()
        .encodeJson<LadybirdSessionHistoryEntry>(
          this as LadybirdSessionHistoryEntry,
        );
  }

  Map<String, dynamic> toMap() {
    return LadybirdSessionHistoryEntryMapper.ensureInitialized()
        .encodeMap<LadybirdSessionHistoryEntry>(
          this as LadybirdSessionHistoryEntry,
        );
  }

  LadybirdSessionHistoryEntryCopyWith<
    LadybirdSessionHistoryEntry,
    LadybirdSessionHistoryEntry,
    LadybirdSessionHistoryEntry
  >
  get copyWith =>
      _LadybirdSessionHistoryEntryCopyWithImpl<
        LadybirdSessionHistoryEntry,
        LadybirdSessionHistoryEntry
      >(this as LadybirdSessionHistoryEntry, $identity, $identity);
  @override
  String toString() {
    return LadybirdSessionHistoryEntryMapper.ensureInitialized().stringifyValue(
      this as LadybirdSessionHistoryEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return LadybirdSessionHistoryEntryMapper.ensureInitialized().equalsValue(
      this as LadybirdSessionHistoryEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return LadybirdSessionHistoryEntryMapper.ensureInitialized().hashValue(
      this as LadybirdSessionHistoryEntry,
    );
  }
}

extension LadybirdSessionHistoryEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LadybirdSessionHistoryEntry, $Out> {
  LadybirdSessionHistoryEntryCopyWith<$R, LadybirdSessionHistoryEntry, $Out>
  get $asLadybirdSessionHistoryEntry => $base.as(
    (v, t, t2) => _LadybirdSessionHistoryEntryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LadybirdSessionHistoryEntryCopyWith<
  $R,
  $In extends LadybirdSessionHistoryEntry,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? step, String? url, bool? current});
  LadybirdSessionHistoryEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LadybirdSessionHistoryEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LadybirdSessionHistoryEntry, $Out>
    implements
        LadybirdSessionHistoryEntryCopyWith<
          $R,
          LadybirdSessionHistoryEntry,
          $Out
        > {
  _LadybirdSessionHistoryEntryCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<LadybirdSessionHistoryEntry> $mapper =
      LadybirdSessionHistoryEntryMapper.ensureInitialized();
  @override
  $R call({int? step, String? url, bool? current}) => $apply(
    FieldCopyWithData({
      if (step != null) #step: step,
      if (url != null) #url: url,
      if (current != null) #current: current,
    }),
  );
  @override
  LadybirdSessionHistoryEntry $make(CopyWithData data) =>
      LadybirdSessionHistoryEntry(
        step: data.get(#step, or: $value.step),
        url: data.get(#url, or: $value.url),
        current: data.get(#current, or: $value.current),
      );

  @override
  LadybirdSessionHistoryEntryCopyWith<$R2, LadybirdSessionHistoryEntry, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LadybirdSessionHistoryEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


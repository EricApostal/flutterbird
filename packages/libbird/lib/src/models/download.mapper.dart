// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'download.dart';

class LadybirdDownloadStatusMapper extends EnumMapper<LadybirdDownloadStatus> {
  LadybirdDownloadStatusMapper._();

  static LadybirdDownloadStatusMapper? _instance;
  static LadybirdDownloadStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LadybirdDownloadStatusMapper._());
    }
    return _instance!;
  }

  static LadybirdDownloadStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  LadybirdDownloadStatus decode(dynamic value) {
    switch (value) {
      case 'in-progress':
        return LadybirdDownloadStatus.inProgress;
      case r'paused':
        return LadybirdDownloadStatus.paused;
      case r'completed':
        return LadybirdDownloadStatus.completed;
      case r'canceled':
        return LadybirdDownloadStatus.canceled;
      case r'failed':
        return LadybirdDownloadStatus.failed;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(LadybirdDownloadStatus self) {
    switch (self) {
      case LadybirdDownloadStatus.inProgress:
        return 'in-progress';
      case LadybirdDownloadStatus.paused:
        return r'paused';
      case LadybirdDownloadStatus.completed:
        return r'completed';
      case LadybirdDownloadStatus.canceled:
        return r'canceled';
      case LadybirdDownloadStatus.failed:
        return r'failed';
    }
  }
}

extension LadybirdDownloadStatusMapperExtension on LadybirdDownloadStatus {
  dynamic toValue() {
    LadybirdDownloadStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<LadybirdDownloadStatus>(this);
  }
}

class LadybirdDownloadMapper extends ClassMapperBase<LadybirdDownload> {
  LadybirdDownloadMapper._();

  static LadybirdDownloadMapper? _instance;
  static LadybirdDownloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LadybirdDownloadMapper._());
      LadybirdDownloadStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LadybirdDownload';

  static int _$id(LadybirdDownload v) => v.id;
  static const Field<LadybirdDownload, int> _f$id = Field('id', _$id);
  static String _$url(LadybirdDownload v) => v.url;
  static const Field<LadybirdDownload, String> _f$url = Field('url', _$url);
  static String _$fileName(LadybirdDownload v) => v.fileName;
  static const Field<LadybirdDownload, String> _f$fileName = Field(
    'fileName',
    _$fileName,
  );
  static String _$destination(LadybirdDownload v) => v.destination;
  static const Field<LadybirdDownload, String> _f$destination = Field(
    'destination',
    _$destination,
  );
  static LadybirdDownloadStatus _$status(LadybirdDownload v) => v.status;
  static const Field<LadybirdDownload, LadybirdDownloadStatus> _f$status =
      Field('status', _$status);
  static int _$downloadedSize(LadybirdDownload v) => v.downloadedSize;
  static const Field<LadybirdDownload, int> _f$downloadedSize = Field(
    'downloadedSize',
    _$downloadedSize,
  );
  static int? _$totalSize(LadybirdDownload v) => v.totalSize;
  static const Field<LadybirdDownload, int> _f$totalSize = Field(
    'totalSize',
    _$totalSize,
    opt: true,
  );
  static String? _$error(LadybirdDownload v) => v.error;
  static const Field<LadybirdDownload, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );

  @override
  final MappableFields<LadybirdDownload> fields = const {
    #id: _f$id,
    #url: _f$url,
    #fileName: _f$fileName,
    #destination: _f$destination,
    #status: _f$status,
    #downloadedSize: _f$downloadedSize,
    #totalSize: _f$totalSize,
    #error: _f$error,
  };

  static LadybirdDownload _instantiate(DecodingData data) {
    return LadybirdDownload(
      id: data.dec(_f$id),
      url: data.dec(_f$url),
      fileName: data.dec(_f$fileName),
      destination: data.dec(_f$destination),
      status: data.dec(_f$status),
      downloadedSize: data.dec(_f$downloadedSize),
      totalSize: data.dec(_f$totalSize),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LadybirdDownload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LadybirdDownload>(map);
  }

  static LadybirdDownload fromJson(String json) {
    return ensureInitialized().decodeJson<LadybirdDownload>(json);
  }
}

mixin LadybirdDownloadMappable {
  String toJson() {
    return LadybirdDownloadMapper.ensureInitialized()
        .encodeJson<LadybirdDownload>(this as LadybirdDownload);
  }

  Map<String, dynamic> toMap() {
    return LadybirdDownloadMapper.ensureInitialized()
        .encodeMap<LadybirdDownload>(this as LadybirdDownload);
  }

  LadybirdDownloadCopyWith<LadybirdDownload, LadybirdDownload, LadybirdDownload>
  get copyWith =>
      _LadybirdDownloadCopyWithImpl<LadybirdDownload, LadybirdDownload>(
        this as LadybirdDownload,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LadybirdDownloadMapper.ensureInitialized().stringifyValue(
      this as LadybirdDownload,
    );
  }

  @override
  bool operator ==(Object other) {
    return LadybirdDownloadMapper.ensureInitialized().equalsValue(
      this as LadybirdDownload,
      other,
    );
  }

  @override
  int get hashCode {
    return LadybirdDownloadMapper.ensureInitialized().hashValue(
      this as LadybirdDownload,
    );
  }
}

extension LadybirdDownloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LadybirdDownload, $Out> {
  LadybirdDownloadCopyWith<$R, LadybirdDownload, $Out>
  get $asLadybirdDownload =>
      $base.as((v, t, t2) => _LadybirdDownloadCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LadybirdDownloadCopyWith<$R, $In extends LadybirdDownload, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? id,
    String? url,
    String? fileName,
    String? destination,
    LadybirdDownloadStatus? status,
    int? downloadedSize,
    int? totalSize,
    String? error,
  });
  LadybirdDownloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LadybirdDownloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LadybirdDownload, $Out>
    implements LadybirdDownloadCopyWith<$R, LadybirdDownload, $Out> {
  _LadybirdDownloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LadybirdDownload> $mapper =
      LadybirdDownloadMapper.ensureInitialized();
  @override
  $R call({
    int? id,
    String? url,
    String? fileName,
    String? destination,
    LadybirdDownloadStatus? status,
    int? downloadedSize,
    Object? totalSize = $none,
    Object? error = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (url != null) #url: url,
      if (fileName != null) #fileName: fileName,
      if (destination != null) #destination: destination,
      if (status != null) #status: status,
      if (downloadedSize != null) #downloadedSize: downloadedSize,
      if (totalSize != $none) #totalSize: totalSize,
      if (error != $none) #error: error,
    }),
  );
  @override
  LadybirdDownload $make(CopyWithData data) => LadybirdDownload(
    id: data.get(#id, or: $value.id),
    url: data.get(#url, or: $value.url),
    fileName: data.get(#fileName, or: $value.fileName),
    destination: data.get(#destination, or: $value.destination),
    status: data.get(#status, or: $value.status),
    downloadedSize: data.get(#downloadedSize, or: $value.downloadedSize),
    totalSize: data.get(#totalSize, or: $value.totalSize),
    error: data.get(#error, or: $value.error),
  );

  @override
  LadybirdDownloadCopyWith<$R2, LadybirdDownload, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LadybirdDownloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


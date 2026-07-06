import 'package:dart_mappable/dart_mappable.dart';

part 'settings.mapper.dart';

@MappableClass()
class LadybirdSearchEngine with LadybirdSearchEngineMappable {
  const LadybirdSearchEngine({required this.name, required this.queryUrl});

  final String name;
  final String queryUrl;
}

@MappableClass()
class LadybirdConfigVariableDefinition
    with LadybirdConfigVariableDefinitionMappable {
  const LadybirdConfigVariableDefinition({
    required this.name,
    required this.title,
    required this.description,
    required this.defaultValue,
    this.arrayElementType,
  });

  final String name;
  final String title;
  final String description;
  final dynamic defaultValue;
  final String? arrayElementType;
}

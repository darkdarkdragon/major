import 'package:build/build.dart';
import 'package:major_graphql/major_graphql.dart';
import 'package:yaml/yaml.dart';
import 'package:meta/meta.dart';
import 'package:get_it/get_it.dart';

const extensions = _Extensions(
  source: '.graphql',
  dartTarget: '.graphql.dart',
  generatedPart: '.graphql.g.dart',
  generatedAstToAlias: '.ast.g.dart',
);

/// The prefix the `major_graphql` is imported into generated files as
final mgPrefix = '_mg';

@immutable
class _Extensions {
  const _Extensions({
    @required this.source,
    @required this.dartTarget,
    @required this.generatedPart,
    @required this.generatedAstToAlias,
  });

  /// The source extension for graphql document files
  final String source;

  /// The target extension for the generated dart files
  final String dartTarget;

  /// The extension for the implementation part files `built_value_generator` will generate
  final String generatedPart;

  /// The extension for the ast `gql_code_gen|ast_builder` will generate.
  ///
  /// We `export ... show document` for use by runtime code
  final String generatedAstToAlias;

  Map<String, List<String>> get forBuild => {
        extensions.source: [extensions.dartTarget],
      };
}

const nestedBuilders = false;

@immutable
class _When {
  const _When({
    @required this.fields,
    @required this.nameNot,
  });

  /// When all these fields are present, the mixin will be added
  final Set<String> fields;

  /// Do not add the mixin for these names
  final Set<String> nameNot;
}

@immutable
class MixinConfig {
  MixinConfig({
    @required this.name,
    @required this.when,
  });
  final String name;

  final _When when;
}

@immutable
class IrreducibleConfig {
  IrreducibleConfig({
    @required this.name,
    bool generate,
  }) : generate = generate ?? true;

  final String name;

  final bool generate;
}

@immutable
class TypeConfig {
  TypeConfig({
    Map<String, String> scalars,
    @required this.replaceTypes,
    @required this.irreducibleTypes,
  }) : scalars = {
          ...defaultPrimitives,
          ...scalars,
        };

  final Map<String, String> scalars;

  final Map<String, String> replaceTypes;

  final Map<String, IrreducibleConfig> irreducibleTypes;

  static final defaultPrimitives = {
    'String': 'String',
    'Int': 'int',
    'Float': 'double',
    'Boolean': 'bool',
    'ID': 'String',
    'int': 'int',
    'bool': 'bool',
    'double': 'double',
    'num': 'num',
    'dynamic': 'dynamic',
    'Object': 'Object',
    'DateTime': 'DateTime',
    'Date': 'DateTime'
  };
}

@immutable
class Configuration {
  const Configuration({
    this.schemaId,
    this.schemaExports,
    this.schemaImports,
    this.forTypes,
    this.forMixins,
    this.convenienceSerializersFunction,
  });

  final AssetId schemaId;
  final List<String> schemaImports;
  final List<String> schemaExports;

  final TypeConfig forTypes;

  final List<MixinConfig> forMixins;

  /// Function injected from an import that wraps serializers in a [ConvenienceSerializers] instance
  ///
  /// defaults to `'_mg.ConvenienceSerializers'`
  final String convenienceSerializersFunction;

  Iterable<String> mixinsWhen(Iterable<String> fieldNames, String name) {
    fieldNames ??= {};
    final fields = fieldNames.toSet();

    return forMixins.where((m) {
      if (m.when.nameNot != null) {
        return !m.when.nameNot.contains(name);
      }
      return true;
    }).where((m) {
      return fields.containsAll(m.when.fields);
    }).map((m) => m.name);
  }

  factory Configuration.fromMap(Map<String, dynamic> config) {
    final schemaConf = config['schema'] is String
        ? <String, Object>{'path': config['schema']}
        : _fromYamlMap<String, Object>(config['schema']);

    final schemaId = AssetId.parse(schemaConf['path'] as String);
    final imports = _fromYamlList<String>(schemaConf['imports'] ?? YamlList());
    final exports = _fromYamlList<String>(schemaConf['exports'] ?? YamlList());
    final convenienceSerializersFunction =
        config['convenienceSerializersFunction'] as String ??
            '${mgPrefix}.ConvenienceSerializers';

    final mixins = _fromYamlList<Map>(config['mixins'] ?? YamlList());
    return Configuration(
      schemaId: schemaId,
      schemaImports: imports,
      schemaExports: exports,
      forTypes: TypeConfig(
        scalars: _fromYamlMap<String, String>(config['scalars'] ?? YamlMap()),
        replaceTypes:
            _fromYamlMap<String, String>(config['replaceTypes'] ?? YamlMap()),
        irreducibleTypes: Map.fromEntries(
          _fromYamlList<YamlMap>(config['irreducibleTypes'] ?? YamlList()).map(
            (m) => MapEntry(
              m['name'] as String,
              IrreducibleConfig(
                name: m['name'] as String,
                generate: m['generate'] as bool,
              ),
            ),
          ),
        ),
      ),
      forMixins: mixins.map(
        (mixinConfig) {
          final when = (mixinConfig['when'] as Map);
          return MixinConfig(
            name: mixinConfig['name'] as String,
            when: _When(
              nameNot: when['nameNot'] != null
                  ? Set.from(_fromYamlList<String>(
                      when['nameNot'],
                    ))
                  : null,
              fields: Set.from(
                _fromYamlList<String>(
                  when['fields'],
                ),
              ),
            ),
          );
        },
      ).toList(),
      convenienceSerializersFunction: convenienceSerializersFunction,
    );
  }
}

List<T> _fromYamlList<T>(dynamic list) => (list as List).cast<T>();
Map<K, T> _fromYamlMap<K, T>(dynamic map) => (map as Map).cast<K, T>();

void configure(Map<String, dynamic> config) =>
    GetIt.instance.registerSingleton<Configuration>(
      Configuration.fromMap(config),
    );

Configuration get configuration => GetIt.instance.get<Configuration>();

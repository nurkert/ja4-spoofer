/// Generic registry item for integer-based TLS registries
/// (cipher suites, extension IDs, signature scheme IDs).
class RegistryItem {
  const RegistryItem({required this.id, required this.name});

  final int id;
  final String name;

  String get hex => '0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  String get label => '$id  $hex  $name';
}

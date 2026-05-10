import 'registry_item.dart';

/// Full registry snapshot used by the app.
class RegistryBundle {
  const RegistryBundle({
    required this.cipherSuites,
    required this.extensions,
    required this.signatureSchemes,
  });

  final List<RegistryItem> cipherSuites;
  final List<RegistryItem> extensions;
  final List<RegistryItem> signatureSchemes;
}

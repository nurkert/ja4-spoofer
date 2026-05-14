import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/models/registry_item.dart';
import '../../core/services/iana_registry_service.dart';
import '../../core/services/profile_service.dart';
import '../../core/models/app_descriptor.dart';
import '../../core/utils/randomize_utils.dart';
import '../../core/utils/shell_utils.dart';

enum TlsStateSource { profile, configurator, randomize }

/// Profile-centric TLS configurator — single source of truth for TLS config.
///
/// Launch config (script paths, target URL, profile dir, --dump, …) is *not*
/// surfaced in the GUI. Power users invoke the shell scripts directly; see
/// `docs/advanced-launch.md`.
class ConfiguratorController extends ChangeNotifier {
  ConfiguratorController({
    IanaRegistryService? registryService,
    ProfileService? profileService,
  }) : _registryService = registryService ?? IanaRegistryService(),
       _profileService = profileService ?? ProfileService() {
    _initializeControllers();
  }

  // ---------- Constants ----------
  static const tlsVersionOptions = <String>['', '1.0', '1.1', '1.2', '1.3'];
  static const sniModeOptions = <String>['', 'present', 'domain', 'none', 'ip'];
  static const boolStringOptions = <String>['', '0', '1'];
  static const alpnPool = <String>['h2', 'http/1.1', 'h3'];

  // ---------- Services ----------
  final IanaRegistryService _registryService;
  final ProfileService _profileService;
  final Random _random = Random.secure();

  // region Filter Controllers
  late final TextEditingController cipherFilterCtrl;
  late final TextEditingController extensionFilterCtrl;
  late final TextEditingController signatureFilterCtrl;
  late final TextEditingController alpnFilterCtrl;
  // endregion

  // region TLS Selections
  String tlsMin = '1.2';
  String tlsMax = '1.3';
  String sniMode = 'present';
  String enableGrease = '0';
  String enablePermutation = '0';
  String? cipherMode;
  String? extensionMode;

  List<RegistryItem> cipherRegistry = List.of(
    IanaRegistryService.fallbackBundle.cipherSuites,
  );
  List<RegistryItem> extensionRegistry = List.of(
    IanaRegistryService.fallbackBundle.extensions,
  );
  List<RegistryItem> signatureRegistry = List.of(
    IanaRegistryService.fallbackBundle.signatureSchemes,
  );

  List<int> selectedCiphers = [];
  List<int> selectedExtensions = [];
  List<int> _selectedSignatures = [];

  /// Snapshot of the original sig-algs from the most recent load (with order
  /// and duplicates intact). JA4 hashes sig-algs in wire order, and Apple
  /// Safari sends 0x0805 twice — losing that quirk breaks 1:1 imitation.
  /// The editor displays the deduped UI list (`_selectedSignatures`) to keep
  /// the ReorderableListView crash-free, but the launch path emits this raw
  /// list when present so the captured wire representation survives.
  /// Cleared by [selectedSignatures] setter so any editor toggle/reorder
  /// switches the launch path back to the (deduped) UI state.
  List<int>? _loadedSignaturesRaw;

  List<int> get selectedSignatures => _selectedSignatures;
  set selectedSignatures(List<int> value) {
    _selectedSignatures = value;
    _loadedSignaturesRaw = null;
  }

  List<String> selectedAlpn = ['h2', 'http/1.1'];
  // endregion

  // region Registry state
  bool registryLoading = false;
  String status = 'ready';
  // endregion

  // region Profile editing state
  /// ID of the profile currently being edited, or null for a new unsaved profile.
  String? editingProfileId;

  /// Whether the loaded profile is a built-in (read-only) profile.
  bool editingIsBuiltIn = false;

  /// Editable metadata for the profile being edited.
  FingerprintProfileMetadata editingMetadata = const FingerprintProfileMetadata(
    name: 'New Profile',
  );

  /// Tracks whether current state differs from the loaded profile.
  bool isDirty = false;

  /// Snapshot of TLS inputs at the time of loading — used for dirty tracking.
  TlsClientHelloInputs? _loadedInputsSnapshot;

  TlsStateSource tlsStateSource = TlsStateSource.configurator;
  String tlsStateSourceLabel = 'Manual defaults';
  // endregion

  late final List<TextEditingController> _filterControllers;

  void _initializeControllers() {
    cipherFilterCtrl = TextEditingController();
    extensionFilterCtrl = TextEditingController();
    signatureFilterCtrl = TextEditingController();
    alpnFilterCtrl = TextEditingController();

    _filterControllers = [
      cipherFilterCtrl,
      extensionFilterCtrl,
      signatureFilterCtrl,
      alpnFilterCtrl,
    ];
    for (final controller in _filterControllers) {
      controller.addListener(_onAnyFieldChanged);
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final controller in _filterControllers) {
      controller.removeListener(_onAnyFieldChanged);
    }
    cipherFilterCtrl.dispose();
    extensionFilterCtrl.dispose();
    signatureFilterCtrl.dispose();
    alpnFilterCtrl.dispose();
    super.dispose();
  }

  void _onAnyFieldChanged() {
    if (!_disposed) {
      _updateDirty();
      notifyListeners();
    }
  }

  void _updateDirty() {
    final snap = _loadedInputsSnapshot;
    if (snap == null) {
      isDirty = true;
      return;
    }
    final current = toTlsClientHelloInputs();
    isDirty =
        current.tlsMinVersion != snap.tlsMinVersion ||
        current.tlsMaxVersion != snap.tlsMaxVersion ||
        current.sniMode != snap.sniMode ||
        current.enableGrease != snap.enableGrease ||
        current.enableChXtnPermutation != snap.enableChXtnPermutation ||
        !_listEquals(current.cipherSuites, snap.cipherSuites) ||
        !_listEquals(current.extensions, snap.extensions) ||
        !_listEquals(current.signatureAlgorithms, snap.signatureAlgorithms) ||
        !_stringListEquals(current.alpnProtocols, snap.alpnProtocols);
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _stringListEquals(List<String> a, List<String> b) =>
      _listEquals(a, b);

  void _setTlsStateSource(TlsStateSource source, String label) {
    tlsStateSource = source;
    tlsStateSourceLabel = label;
  }

  // ---------- Setters ----------
  void setTlsMin(String value) {
    tlsMin = value;
    _setTlsStateSource(TlsStateSource.configurator, 'Manual TLS edit');
    _updateDirty();
    notifyListeners();
  }

  void setTlsMax(String value) {
    tlsMax = value;
    _setTlsStateSource(TlsStateSource.configurator, 'Manual TLS edit');
    _updateDirty();
    notifyListeners();
  }

  void setSniMode(String value) {
    sniMode = value;
    _setTlsStateSource(TlsStateSource.configurator, 'Manual TLS edit');
    _updateDirty();
    notifyListeners();
  }

  void setEnableGrease(String value) {
    enableGrease = value;
    _setTlsStateSource(TlsStateSource.configurator, 'Manual TLS edit');
    _updateDirty();
    notifyListeners();
  }

  void setEnablePermutation(String value) {
    enablePermutation = value;
    _setTlsStateSource(TlsStateSource.configurator, 'Manual TLS edit');
    _updateDirty();
    notifyListeners();
  }

  void setEditingName(String value) {
    editingMetadata = editingMetadata.copyWith(name: value);
    notifyListeners();
  }

  void setEditingVersion(String? value) {
    editingMetadata = editingMetadata.copyWith(version: value);
    notifyListeners();
  }

  void setEditingIconUrl(String? value) {
    editingMetadata = editingMetadata.copyWith(iconUrl: value);
    notifyListeners();
  }

  void setEditingProfileFormat(String? value) {
    editingMetadata = editingMetadata.copyWith(profileFormat: value);
    notifyListeners();
  }

  // ---------- Registry Loading ----------
  /// Loads IANA registries from the chosen [source]. The service falls
  /// through to the bundled snapshot or the hardcoded fallback list when
  /// the requested source is unavailable.
  Future<void> loadRegistries({IanaSource source = IanaSource.bundled}) async {
    registryLoading = true;
    status = switch (source) {
      IanaSource.online => 'loading IANA registries (online)...',
      IanaSource.bundled => 'loading bundled IANA snapshot...',
      IanaSource.disabled => 'IANA name resolution disabled',
    };
    notifyListeners();

    try {
      final bundle = await _registryService.load(source);
      cipherRegistry = bundle.cipherSuites;
      extensionRegistry = bundle.extensions;
      signatureRegistry = bundle.signatureSchemes;

      selectedCiphers = _dedupeIntSelection(selectedCiphers);
      selectedExtensions = _dedupeIntSelection(selectedExtensions);
      _selectedSignatures = _dedupeIntSelection(_selectedSignatures);

      status = switch (source) {
        IanaSource.disabled => 'hex only (IANA disabled in Privacy settings)',
        _ =>
          'ready (ciphers: ${cipherRegistry.length}, '
              'extensions: ${extensionRegistry.length}, '
              'signatures: ${signatureRegistry.length})',
      };
    } catch (e) {
      cipherRegistry = List.of(IanaRegistryService.fallbackBundle.cipherSuites);
      extensionRegistry = List.of(
        IanaRegistryService.fallbackBundle.extensions,
      );
      signatureRegistry = List.of(
        IanaRegistryService.fallbackBundle.signatureSchemes,
      );
      selectedCiphers = _dedupeIntSelection(selectedCiphers);
      selectedExtensions = _dedupeIntSelection(selectedExtensions);
      _selectedSignatures = _dedupeIntSelection(_selectedSignatures);
      status = 'registry load failed, fallback lists active';
    } finally {
      registryLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  // ---------- Profile Editing ----------
  /// Resets all fields to a blank "New Profile" state.
  void resetToDefaults() {
    editingProfileId = null;
    editingIsBuiltIn = false;
    editingMetadata = const FingerprintProfileMetadata(name: 'New Profile');

    tlsMin = '1.2';
    tlsMax = '1.3';
    sniMode = 'present';
    enableGrease = '0';
    enablePermutation = '0';
    cipherMode = null;
    extensionMode = null;
    selectedCiphers = [];
    selectedExtensions = [];
    selectedSignatures = [];
    selectedAlpn = ['h2', 'http/1.1'];

    _loadedInputsSnapshot = null;
    isDirty = false;
    _setTlsStateSource(TlsStateSource.configurator, 'New Profile');
    notifyListeners();
  }

  /// Loads a freshly-rolled random profile into the editor as an unsaved
  /// draft. Drops `profileId` so the next Save creates a new catalog entry,
  /// pre-fills the metadata name with [suggestedName], and marks the editor
  /// dirty so the Save button is enabled immediately.
  void loadFromRandomRoll(
    FingerprintProfile profile, {
    required String suggestedName,
  }) {
    final inputs = profile.inputs;
    editingProfileId = null;
    editingIsBuiltIn = false;
    editingMetadata = FingerprintProfileMetadata(
      name: suggestedName,
      source: 'manual',
      profileFormat: profile.metadata.profileFormat,
    );

    tlsMin = inputs.tlsMinVersion;
    tlsMax = inputs.tlsMaxVersion;
    sniMode = inputs.sniMode;
    enableGrease = inputs.enableGrease ? '1' : '0';
    enablePermutation = inputs.enableChXtnPermutation ? '1' : '0';
    cipherMode = inputs.cipherMode;
    extensionMode = inputs.extensionMode;
    selectedCiphers = _dedupeIntSelection(inputs.cipherSuites);
    selectedAlpn = _dedupeStringSelection(inputs.alpnProtocols);
    _selectedSignatures = _dedupeIntSelection(inputs.signatureAlgorithms);
    _loadedSignaturesRaw = List<int>.from(inputs.signatureAlgorithms);
    selectedExtensions = _dedupeIntSelection(inputs.extensions);

    _setTlsStateSource(TlsStateSource.randomize, suggestedName);
    _loadedInputsSnapshot = null; // Random profile is "dirty by design".
    isDirty = true;
    notifyListeners();
  }

  /// Loads a profile into the editor, setting all TLS fields + metadata.
  void loadProfile(FingerprintProfile profile) {
    final inputs = profile.inputs;
    editingProfileId = profile.profileId;
    editingIsBuiltIn = profile.isBuiltIn;
    editingMetadata = profile.metadata;

    tlsMin = inputs.tlsMinVersion;
    tlsMax = inputs.tlsMaxVersion;
    sniMode = inputs.sniMode;
    enableGrease = inputs.enableGrease ? '1' : '0';
    enablePermutation = inputs.enableChXtnPermutation ? '1' : '0';
    cipherMode = inputs.cipherMode;
    extensionMode = inputs.extensionMode;
    selectedCiphers = _dedupeIntSelection(inputs.cipherSuites);
    selectedAlpn = _dedupeStringSelection(inputs.alpnProtocols);
    _selectedSignatures = _dedupeIntSelection(inputs.signatureAlgorithms);
    _loadedSignaturesRaw = List<int>.from(inputs.signatureAlgorithms);
    selectedExtensions = _dedupeIntSelection(inputs.extensions);

    _setTlsStateSource(TlsStateSource.profile, profile.metadata.name);
    _loadedInputsSnapshot = inputs;
    isDirty = false;
    notifyListeners();
  }

  /// Saves the current state as a profile (overwrites existing for non-built-in,
  /// creates new otherwise).
  Future<FingerprintProfile> saveProfile() async {
    final profile = toFingerprintProfile();
    await _profileService.save(profile);
    editingProfileId = profile.profileId;
    editingIsBuiltIn = false;
    editingMetadata = profile.metadata;
    _loadedInputsSnapshot = profile.inputs;
    isDirty = false;
    status = 'profile "${editingMetadata.name}" saved';
    notifyListeners();
    return profile;
  }

  /// Creates a new profile based on the current state with a new name.
  Future<FingerprintProfile> duplicateAsNew(String newName) async {
    final id = 'manual-${DateTime.now().millisecondsSinceEpoch}';
    editingProfileId = id;
    editingIsBuiltIn = false;
    editingMetadata = editingMetadata.copyWith(name: newName, source: 'manual');
    return saveProfile();
  }

  /// Clones an existing profile into the editor as an unsaved copy.
  ///
  /// Used by the profile browser's "Duplicate" action: copies all TLS state
  /// from [source] into the editor, drops `editingProfileId` so the next save
  /// creates a new file, and marks the editor dirty so Save lights up.
  void cloneIntoEditor(FingerprintProfile source) {
    final inputs = source.inputs;
    editingProfileId = null;
    editingIsBuiltIn = false;
    editingMetadata = FingerprintProfileMetadata(
      name: '${source.metadata.name} (copy)',
      source: 'manual',
      profileFormat: source.metadata.profileFormat,
      iconUrl: source.metadata.iconUrl,
      version: source.metadata.version,
    );

    tlsMin = inputs.tlsMinVersion;
    tlsMax = inputs.tlsMaxVersion;
    sniMode = inputs.sniMode;
    enableGrease = inputs.enableGrease ? '1' : '0';
    enablePermutation = inputs.enableChXtnPermutation ? '1' : '0';
    cipherMode = inputs.cipherMode;
    extensionMode = inputs.extensionMode;
    selectedCiphers = _dedupeIntSelection(inputs.cipherSuites);
    selectedAlpn = _dedupeStringSelection(inputs.alpnProtocols);
    _selectedSignatures = _dedupeIntSelection(inputs.signatureAlgorithms);
    _loadedSignaturesRaw = List<int>.from(inputs.signatureAlgorithms);
    selectedExtensions = _dedupeIntSelection(inputs.extensions);

    _loadedInputsSnapshot = null;
    isDirty = true;
    _setTlsStateSource(
      TlsStateSource.profile,
      '${source.metadata.name} (copy)',
    );
    notifyListeners();
  }

  /// Snapshot current TLS state into a [TlsClientHelloInputs].
  TlsClientHelloInputs toTlsClientHelloInputs() {
    return TlsClientHelloInputs(
      tlsMinVersion: tlsMin,
      tlsMaxVersion: tlsMax,
      cipherSuites: List.of(selectedCiphers),
      alpnProtocols: List.of(selectedAlpn),
      extensions: List.of(selectedExtensions),
      signatureAlgorithms: List.of(_loadedSignaturesRaw ?? _selectedSignatures),
      enableGrease: enableGrease == '1',
      enableChXtnPermutation: enablePermutation == '1',
      sniMode: sniMode,
      cipherMode: cipherMode,
      extensionMode: extensionMode,
    );
  }

  /// Snapshot current state with metadata into a [FingerprintProfile].
  FingerprintProfile toFingerprintProfile() {
    return FingerprintProfile(
      profileId:
          editingProfileId ?? 'manual-${DateTime.now().millisecondsSinceEpoch}',
      metadata: editingMetadata.copyWith(capturedAt: DateTime.now()),
      inputs: toTlsClientHelloInputs(),
    );
  }

  // ---------- Randomization ----------
  void randomizeAll() {
    final versions = randomizeTlsVersions(_random);
    enableGrease = '0';
    enablePermutation = '0';
    cipherMode = null;
    extensionMode = null;
    sniMode = 'present';
    tlsMin = versions.tlsMin;
    tlsMax = versions.tlsMax;
    selectedAlpn = randomizeAlpn(_random);
    selectedCiphers = randomizeCiphers(cipherRegistry, _random);
    selectedSignatures = randomizeSignatures(signatureRegistry, _random);
    selectedExtensions = randomizeExtensions(extensionRegistry, _random);
    _setTlsStateSource(TlsStateSource.randomize, 'Full Random');
    _updateDirty();
    notifyListeners();
  }

  void smartRandomize(
    String? profileFormat, {
    AppTlsDefaults? tlsDefaults,
    RandomizePaddingConfig paddingConfig = const RandomizePaddingConfig.none(),
  }) {
    if (profileFormat != null) {
      final inputs = smartRandomizeInputs(
        profileFormat,
        _random,
        tlsDefaults: tlsDefaults,
        paddingConfig: paddingConfig,
      );
      tlsMin = inputs.tlsMinVersion;
      tlsMax = inputs.tlsMaxVersion;
      selectedAlpn = inputs.alpnProtocols;
      enableGrease = inputs.enableGrease ? '1' : '0';
      enablePermutation = inputs.enableChXtnPermutation ? '1' : '0';
      cipherMode = inputs.cipherMode;
      extensionMode = inputs.extensionMode;
      selectedCiphers = inputs.cipherSuites;
      selectedExtensions = inputs.extensions;
      selectedSignatures = inputs.signatureAlgorithms;
      _setTlsStateSource(TlsStateSource.randomize, 'Smart Random');
    } else {
      randomizeAll();
      return;
    }
    _updateDirty();
    notifyListeners();
  }

  void partialRandomizeCiphers() {
    selectedCiphers = randomizeCiphers(cipherRegistry, _random);
    _setTlsStateSource(TlsStateSource.randomize, 'Randomized ciphers');
    _updateDirty();
    notifyListeners();
  }

  void partialRandomizeExtensions() {
    selectedExtensions = randomizeExtensions(extensionRegistry, _random);
    _setTlsStateSource(TlsStateSource.randomize, 'Randomized extensions');
    _updateDirty();
    notifyListeners();
  }

  void partialRandomizeSignatures() {
    selectedSignatures = randomizeSignatures(signatureRegistry, _random);
    _setTlsStateSource(TlsStateSource.randomize, 'Randomized signatures');
    _updateDirty();
    notifyListeners();
  }

  void partialRandomizeAlpn() {
    selectedAlpn = randomizeAlpn(_random);
    _setTlsStateSource(TlsStateSource.randomize, 'Randomized ALPN');
    _updateDirty();
    notifyListeners();
  }

  // ---------- Command Preview ----------
  /// Renders the TLS-payload args the GUI would forward to a launch script.
  ///
  /// This is a *preview* of the TLS-relevant CLI flags only — script path,
  /// target URL, profile directory, --dump/--show-config/--dry-run/--set and
  /// other deep-dive launch knobs are intentionally not surfaced in the GUI;
  /// see `docs/advanced-launch.md` for direct script invocation.
  String renderCommandPreview() {
    final args = _buildScriptArgs();
    final command = <String>['scripts/run_<app>_with_ja4.sh', ...args];
    final lines = <String>[];
    for (var i = 0; i < command.length; i++) {
      final token = shellQuote(command[i]);
      if (i == command.length - 1) {
        lines.add('  $token');
      } else if (i == 0) {
        lines.add('$token \\');
      } else {
        lines.add('  $token \\');
      }
    }
    return lines.join('\n');
  }

  List<String> _buildScriptArgs() {
    final args = <String>[];

    if (tlsMin.isNotEmpty) args.addAll(['--tls-min', tlsMin]);
    if (tlsMax.isNotEmpty) args.addAll(['--tls-max', tlsMax]);
    if (enableGrease.isNotEmpty) args.addAll(['--enable-grease', enableGrease]);
    if (enablePermutation.isNotEmpty) {
      args.addAll(['--enable-ch-xtn-permutation', enablePermutation]);
    }
    if (selectedCiphers.isNotEmpty) {
      args.addAll(['--cipher-suites', selectedCiphers.join(',')]);
    }
    if (selectedAlpn.isNotEmpty) {
      args.addAll(['--alpn', selectedAlpn.join(',')]);
    }
    if (selectedSignatures.isNotEmpty) {
      args.addAll(['--signature-algorithms', selectedSignatures.join(',')]);
    }
    if (selectedExtensions.isNotEmpty) {
      args.addAll(['--extension-order', selectedExtensions.join(',')]);
    }
    if (sniMode.isNotEmpty) args.addAll(['--sni-mode', sniMode]);

    return args;
  }

  // ---------- Selection mutations ----------
  void setIntSelection(
    List<int> next, {
    required void Function(List<int>) setter,
  }) {
    setter(next);
    _updateDirty();
    notifyListeners();
  }

  void setStringSelection(
    List<String> next, {
    required void Function(List<String>) setter,
  }) {
    setter(next);
    _updateDirty();
    notifyListeners();
  }

  void toggleIntSelection(
    int id, {
    required List<int> Function() currentGetter,
    required void Function(List<int>) setter,
  }) {
    final next = List<int>.from(currentGetter());
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setter(next);
    _updateDirty();
    notifyListeners();
  }

  void reorderSelection<T>(
    int oldIndex,
    int newIndex, {
    required List<T> Function() currentGetter,
    required void Function(List<T>) setter,
  }) {
    if (oldIndex < newIndex) newIndex -= 1;
    final next = List<T>.from(currentGetter());
    next.insert(newIndex, next.removeAt(oldIndex));
    setter(next);
    _updateDirty();
    notifyListeners();
  }

  void removeIntSelectionAt(
    int index, {
    required List<int> Function() currentGetter,
    required void Function(List<int>) setter,
  }) {
    final next = List<int>.from(currentGetter())..removeAt(index);
    setter(next);
    _updateDirty();
    notifyListeners();
  }

  void toggleStringSelection(
    String value, {
    required List<String> Function() currentGetter,
    required void Function(List<String>) setter,
  }) {
    final next = List<String>.from(currentGetter());
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    setter(next);
    _updateDirty();
    notifyListeners();
  }

  void removeStringSelectionAt(
    int index, {
    required List<String> Function() currentGetter,
    required void Function(List<String>) setter,
  }) {
    final next = List<String>.from(currentGetter())..removeAt(index);
    setter(next);
    _updateDirty();
    notifyListeners();
  }

  // ---------- Utility ----------
  /// Deduplicates a selection while preserving order and unknown IDs.
  ///
  /// Imported profiles may contain IDs that are not present in the local
  /// registry snapshot yet; those values must survive a registry reload.
  List<int> _dedupeIntSelection(List<int> selection) {
    final out = <int>[];
    final seen = <int>{};
    for (final id in selection) {
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  List<String> _dedupeStringSelection(List<String> selection) {
    final out = <String>[];
    final seen = <String>{};
    for (final val in selection) {
      if (seen.add(val)) out.add(val);
    }
    return out;
  }
}

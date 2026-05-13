import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/controllers/profile_catalog_controller.dart';
import '../../core/models/fingerprint_profile.dart';
import '../settings/settings_controller.dart';
import 'configurator_controller.dart';
import 'widgets/alpn_editor_card.dart';
import 'widgets/command_console_card.dart';
import 'widgets/profile_browser_pane.dart';
import 'widgets/profile_editor_header.dart';
import 'widgets/registry_editor_card.dart';
import 'widgets/tls_options_card.dart';

class ConfiguratorPage extends StatelessWidget {
  const ConfiguratorPage({
    super.key,
    required this.controller,
    required this.profileCatalogController,
    required this.settingsController,
    required this.onNavigateToQuickLaunch,
  });

  final ConfiguratorController controller;
  final ProfileCatalogController profileCatalogController;
  final SettingsController settingsController;
  final VoidCallback onNavigateToQuickLaunch;

  Future<void> _copyCommandPreview(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: controller.renderCommandPreview()),
    );
  }

  void _onProfileSelected(FingerprintProfile profile) {
    controller.loadProfile(profile);
    unawaited(profileCatalogController.selectProfile(profile.profileId));
  }

  void _onNewProfile() {
    controller.resetToDefaults();
    unawaited(profileCatalogController.selectProfile(null));
  }

  void _onDuplicate(FingerprintProfile profile) {
    controller.cloneIntoEditor(profile);
    unawaited(profileCatalogController.selectProfile(null));
  }

  Future<void> _onDelete(
    BuildContext context,
    FingerprintProfile profile,
  ) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: Text('Delete "${profile.metadata.name}"?'),
        description: const Text(
          'This permanently removes the profile from disk.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final wasActive = controller.editingProfileId == profile.profileId;
    await profileCatalogController.deleteProfile(profile.profileId);
    if (wasActive) {
      controller.resetToDefaults();
    }
    if (context.mounted) {
      ShadSonner.of(context).show(
        ShadToast(description: Text('Deleted "${profile.metadata.name}"')),
      );
    }
  }

  void _showSaveAsDialog(BuildContext context) {
    final nameCtrl = TextEditingController(
      text: controller.editingMetadata.name,
    );
    String? selectedFormat = controller.editingMetadata.profileFormat;
    unawaited(
      showShadDialog(
        context: context,
        builder: (dialogContext) => _SaveAsDialog(
          nameCtrl: nameCtrl,
          initialFormat: selectedFormat,
          onSave: (name, format) async {
            controller.setEditingProfileFormat(format);
            final profile = await controller.duplicateAsNew(name);
            await profileCatalogController.refresh();
            await profileCatalogController.selectProfile(profile.profileId);
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
              ShadSonner.of(
                context,
              ).show(ShadToast(description: Text('Profile "$name" saved')));
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, profileCatalogController]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final contentPadding = constraints.maxWidth >= 1100 ? 20.0 : 12.0;
            final wideCanvas = constraints.maxWidth >= 1500;
            final twoColumnVectorCards = constraints.maxWidth >= 1280;

            final showPane = constraints.maxWidth >= 900;

            final scrollContent = SingleChildScrollView(
              padding: EdgeInsets.all(contentPadding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1780),
                  child: wideCanvas
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 9,
                              child: _buildMainColumn(
                                context,
                                twoColumnVectorCards: twoColumnVectorCards,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(flex: 7, child: _buildSideColumn(context)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMainColumn(
                              context,
                              twoColumnVectorCards: twoColumnVectorCards,
                            ),
                            const SizedBox(height: 14),
                            _buildSideColumn(context),
                          ],
                        ),
                ),
              ),
            );

            if (!showPane) return scrollContent;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    contentPadding,
                    contentPadding,
                    0,
                    contentPadding,
                  ),
                  child: SizedBox(
                    width: 244,
                    child: ProfileBrowserPane(
                      controller: controller,
                      profileCatalogController: profileCatalogController,
                      onProfileSelected: _onProfileSelected,
                      onDuplicate: _onDuplicate,
                      onDelete: (p) => unawaited(_onDelete(context, p)),
                      onNewProfile: _onNewProfile,
                    ),
                  ),
                ),
                Expanded(child: scrollContent),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMainColumn(
    BuildContext context, {
    required bool twoColumnVectorCards,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileEditorHeader(
          controller: controller,
          onSave: () => unawaited(() async {
            final profile = await controller.saveProfile();
            await profileCatalogController.refresh();
            await profileCatalogController.selectProfile(profile.profileId);
          }()),
          onSaveAs: () => _showSaveAsDialog(context),
          onReloadRegistries: () => unawaited(
            controller.loadRegistries(
              source: settingsController.settings.ianaSource,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TlsOptionsCard(controller: controller),
        const SizedBox(height: 12),
        if (twoColumnVectorCards)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCipherCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildSignatureCard()),
            ],
          )
        else ...[
          _buildCipherCard(),
          const SizedBox(height: 12),
          _buildSignatureCard(),
        ],
        const SizedBox(height: 12),
        if (twoColumnVectorCards)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildExtensionCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildAlpnCard()),
            ],
          )
        else ...[
          _buildExtensionCard(),
          const SizedBox(height: 12),
          _buildAlpnCard(),
        ],
      ],
    );
  }

  Widget _buildSideColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ShadSeparator.horizontal(),
        const SizedBox(height: 12),
        CommandConsoleCard(
          commandPreview: controller.renderCommandPreview(),
          status: controller.status,
          onCopyCommand: () => unawaited(_copyCommandPreview(context)),
          onNavigateToQuickLaunch: onNavigateToQuickLaunch,
        ),
      ],
    );
  }

  Widget _buildCipherCard() {
    return RegistryEditorCard(
      title: 'Cipher Suites',
      subtitle:
          'IANA list. Selected order maps directly to --cipher-suites and affects JA4.',
      registry: controller.cipherRegistry,
      selected: controller.selectedCiphers,
      filterController: controller.cipherFilterCtrl,
      onToggle: (id) => controller.toggleIntSelection(
        id,
        currentGetter: () => controller.selectedCiphers,
        setter: (next) => controller.selectedCiphers = next,
      ),
      onReplaceSelection: (next) => controller.setIntSelection(
        next,
        setter: (value) => controller.selectedCiphers = value,
      ),
      onReorder: (old, nw) => controller.reorderSelection<int>(
        old,
        nw,
        currentGetter: () => controller.selectedCiphers,
        setter: (next) => controller.selectedCiphers = next,
      ),
      onRemove: (index) => controller.removeIntSelectionAt(
        index,
        currentGetter: () => controller.selectedCiphers,
        setter: (next) => controller.selectedCiphers = next,
      ),
    );
  }

  Widget _buildSignatureCard() {
    return RegistryEditorCard(
      title: 'Signature Schemes',
      subtitle:
          'IANA list. Selected order maps directly to --signature-algorithms.',
      registry: controller.signatureRegistry,
      selected: controller.selectedSignatures,
      filterController: controller.signatureFilterCtrl,
      onToggle: (id) => controller.toggleIntSelection(
        id,
        currentGetter: () => controller.selectedSignatures,
        setter: (next) => controller.selectedSignatures = next,
      ),
      onReplaceSelection: (next) => controller.setIntSelection(
        next,
        setter: (value) => controller.selectedSignatures = value,
      ),
      onReorder: (old, nw) => controller.reorderSelection<int>(
        old,
        nw,
        currentGetter: () => controller.selectedSignatures,
        setter: (next) => controller.selectedSignatures = next,
      ),
      onRemove: (index) => controller.removeIntSelectionAt(
        index,
        currentGetter: () => controller.selectedSignatures,
        setter: (next) => controller.selectedSignatures = next,
      ),
    );
  }

  Widget _buildExtensionCard() {
    return RegistryEditorCard(
      title: 'Extensions',
      subtitle: 'IANA list. Selected order maps directly to --extension-order.',
      registry: controller.extensionRegistry,
      selected: controller.selectedExtensions,
      filterController: controller.extensionFilterCtrl,
      onToggle: (id) => controller.toggleIntSelection(
        id,
        currentGetter: () => controller.selectedExtensions,
        setter: (next) => controller.selectedExtensions = next,
      ),
      onReplaceSelection: (next) => controller.setIntSelection(
        next,
        setter: (value) => controller.selectedExtensions = value,
      ),
      onReorder: (old, nw) => controller.reorderSelection<int>(
        old,
        nw,
        currentGetter: () => controller.selectedExtensions,
        setter: (next) => controller.selectedExtensions = next,
      ),
      onRemove: (index) => controller.removeIntSelectionAt(
        index,
        currentGetter: () => controller.selectedExtensions,
        setter: (next) => controller.selectedExtensions = next,
      ),
    );
  }

  Widget _buildAlpnCard() {
    return AlpnEditorCard(
      available: ConfiguratorController.alpnPool,
      selected: controller.selectedAlpn,
      filterController: controller.alpnFilterCtrl,
      onToggle: (value) => controller.toggleStringSelection(
        value,
        currentGetter: () => controller.selectedAlpn,
        setter: (next) => controller.selectedAlpn = next,
      ),
      onReplaceSelection: (next) => controller.setStringSelection(
        next,
        setter: (value) => controller.selectedAlpn = value,
      ),
      onReorder: (old, nw) => controller.reorderSelection<String>(
        old,
        nw,
        currentGetter: () => controller.selectedAlpn,
        setter: (next) => controller.selectedAlpn = next,
      ),
      onRemove: (index) => controller.removeStringSelectionAt(
        index,
        currentGetter: () => controller.selectedAlpn,
        setter: (next) => controller.selectedAlpn = next,
      ),
    );
  }
}

// ---------- Dialogs ----------

class _SaveAsDialog extends StatefulWidget {
  const _SaveAsDialog({
    required this.nameCtrl,
    required this.initialFormat,
    required this.onSave,
  });

  final TextEditingController nameCtrl;
  final String? initialFormat;
  final void Function(String name, String? format) onSave;

  @override
  State<_SaveAsDialog> createState() => _SaveAsDialogState();
}

class _SaveAsDialogState extends State<_SaveAsDialog> {
  late String? _selectedFormat;

  static const _formatOptions = <(String?, String)>[
    (null, 'Universal (any)'),
    ('nss', 'NSS (Firefox)'),
    ('boringssl', 'BoringSSL (Chromium)'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.initialFormat;
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('Save As Profile'),
      description: const Text(
        'Save the current TLS configuration as a new profile.',
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadInput(
            controller: widget.nameCtrl,
            placeholder: const Text('e.g. Chrome 130 macOS'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 110,
                child: Text('Format:', style: TextStyle(fontSize: 13)),
              ),
              Expanded(
                child: ShadSelect<String?>(
                  placeholder: const Text('Universal (any)'),
                  options: _formatOptions
                      .map(
                        (opt) => ShadOption(value: opt.$1, child: Text(opt.$2)),
                      )
                      .toList(),
                  selectedOptionBuilder: (context, value) {
                    final label = _formatOptions
                        .firstWhere(
                          (o) => o.$1 == value,
                          orElse: () => (null, 'Universal (any)'),
                        )
                        .$2;
                    return Text(label);
                  },
                  onChanged: (v) => setState(() => _selectedFormat = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ShadButton.outline(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ShadButton(
                onPressed: () {
                  final name = widget.nameCtrl.text.trim();
                  if (name.isNotEmpty) {
                    widget.onSave(name, _selectedFormat);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

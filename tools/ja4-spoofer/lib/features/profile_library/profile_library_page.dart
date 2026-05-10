import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/widgets/labeled_fields.dart';
import '../../app/widgets/safe_network_icon.dart';
import '../../app/widgets/section_card.dart';
import '../../core/models/app_descriptor.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/utils/compatibility_checker.dart';
import 'profile_library_controller.dart';

class ProfileLibraryPage extends StatefulWidget {
  const ProfileLibraryPage({
    super.key,
    required this.controller,
    this.apps = const [],
    this.onEditProfile,
  });

  final ProfileLibraryController controller;
  final List<AppDescriptor> apps;

  /// Called when the user wants to edit a profile in the Configurator.
  final void Function(FingerprintProfile profile)? onEditProfile;

  @override
  State<ProfileLibraryPage> createState() => _ProfileLibraryPageState();
}

class _ProfileLibraryPageState extends State<ProfileLibraryPage> {
  late final TextEditingController _filterCtrl;

  @override
  void initState() {
    super.initState();
    widget.controller.updateApps(widget.apps);
    _filterCtrl = TextEditingController();
    _filterCtrl.addListener(
      () => widget.controller.setFilter(_filterCtrl.text),
    );
    unawaited(widget.controller.loadProfiles());
  }

  @override
  void didUpdateWidget(ProfileLibraryPage old) {
    super.didUpdateWidget(old);
    if (old.apps != widget.apps) {
      widget.controller.updateApps(widget.apps);
    }
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 2, child: _buildProfileList()),
                              const SizedBox(width: 16),
                              Expanded(flex: 3, child: _buildDetailPanel()),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 350,
                                  child: _buildProfileList(),
                                ),
                                const SizedBox(height: 16),
                                _buildDetailPanel(),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileList() {
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profile Library',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.controller.profiles.length} profiles',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          if (widget.controller.status.isNotEmpty) ...[
            const SizedBox(height: 6),
            ShadBadge.secondary(child: Text(widget.controller.status)),
          ],
          const SizedBox(height: 10),
          LabeledInputField(
            label: 'Search',
            controller: _filterCtrl,
            hint: 'Filter by name, source...',
          ),
          const SizedBox(height: 10),
          Expanded(
            child: widget.controller.loading
                ? const Center(child: CircularProgressIndicator())
                : widget.controller.filteredProfiles.isEmpty
                ? const Center(
                    child: Text(
                      'No profiles found.\nImport a FCS JSON file to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.controller.filteredProfiles.length,
                    itemBuilder: (context, index) {
                      final profile = widget.controller.filteredProfiles[index];
                      final isSelected =
                          widget.controller.selectedProfileId ==
                          profile.profileId;
                      return _ProfileListTile(
                        profile: profile,
                        isSelected: isSelected,
                        onTap: () => unawaited(
                          widget.controller.selectProfile(profile.profileId),
                        ),
                        onDelete: profile.isBuiltIn
                            ? null
                            : () => unawaited(
                                widget.controller.deleteProfile(
                                  profile.profileId,
                                ),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel() {
    final profile = widget.controller.selectedProfile;
    if (profile == null) {
      return ShadCard(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: Text(
            'Select a profile to see details.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _ProfileDetailCard(
            profile: profile,
            onEditProfile: widget.onEditProfile,
            controller: widget.controller,
          ),
          const SizedBox(height: 12),
          _AppCompatibilityCard(
            results: widget.controller.compatibilityResults,
          ),
        ],
      ),
    );
  }
}

class _ProfileListTile extends StatelessWidget {
  const _ProfileListTile({
    required this.profile,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
  });

  final FingerprintProfile profile;
  final bool isSelected;
  final VoidCallback onTap;

  /// Null for built-in profiles (shows a lock icon instead).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.accent : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? theme.colorScheme.border : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (profile.metadata.iconUrl != null) ...[
              LimitedBox(
                maxWidth: 112,
                child: SafeNetworkIcon(
                  url: profile.metadata.iconUrl,
                  size: 56,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.metadata.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      ShadBadge.outline(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: Text(
                          profile.metadata.source,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      if (profile.metadata.version != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            profile.metadata.version!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: onDelete,
                child: Icon(
                  LucideIcons.trash2,
                  size: 14,
                  color: theme.colorScheme.destructive,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  LucideIcons.lock,
                  size: 14,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetailCard extends StatelessWidget {
  const _ProfileDetailCard({
    required this.profile,
    required this.controller,
    this.onEditProfile,
  });

  final FingerprintProfile profile;
  final ProfileLibraryController controller;
  final void Function(FingerprintProfile profile)? onEditProfile;

  @override
  Widget build(BuildContext context) {
    final inputs = profile.inputs;
    return SectionCard(
      title: profile.metadata.name,
      subtitle: 'Profile ID: ${profile.profileId}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (profile.isBuiltIn) ...[
            Icon(LucideIcons.lock, size: 12, color: Colors.grey),
            const SizedBox(width: 6),
          ],
          ShadBadge.secondary(child: Text(profile.metadata.source)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (profile.metadata.version != null)
            _Row('Version', profile.metadata.version!),
          _Row(
            'TLS Version',
            '${inputs.tlsMinVersion} \u2013 ${inputs.tlsMaxVersion}',
          ),
          _Row('SNI Mode', inputs.sniMode),
          _Row('Cipher Suites', '${inputs.cipherSuites.length} selected'),
          _Row('Extensions', '${inputs.extensions.length} selected'),
          _Row(
            'Signature Algs',
            '${inputs.signatureAlgorithms.length} selected',
          ),
          _Row('ALPN', inputs.alpnProtocols.join(', ')),
          const SizedBox(height: 8),
          const ShadSeparator.horizontal(),
          const SizedBox(height: 8),
          _DetailSection(
            label: 'Ciphers',
            text: controller.formatCiphers(inputs.cipherSuites),
          ),
          const SizedBox(height: 6),
          _DetailSection(
            label: 'Extensions',
            text: controller.formatExtensions(inputs.extensions),
          ),
          const SizedBox(height: 6),
          _DetailSection(
            label: 'Signature Algorithms',
            text: controller.formatSignatures(inputs.signatureAlgorithms),
          ),
          // Edit button
          if (onEditProfile != null) ...[
            const SizedBox(height: 12),
            const ShadSeparator.horizontal(),
            const SizedBox(height: 8),
            if (profile.isBuiltIn)
              ShadButton.outline(
                onPressed: () => onEditProfile!(profile),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.copy, size: 14),
                    SizedBox(width: 6),
                    Text('Duplicate & Edit'),
                  ],
                ),
              )
            else
              ShadButton.outline(
                onPressed: () => onEditProfile!(profile),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.pencil, size: 14),
                    SizedBox(width: 6),
                    Text('Edit in Configurator'),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _AppCompatibilityCard extends StatelessWidget {
  const _AppCompatibilityCard({required this.results});

  final List<CompatibilityResult> results;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'App Compatibility',
      subtitle:
          'Checks whether this profile is compatible with the patched browsers.',
      child: results.isEmpty
          ? const Text(
              'No apps with TLS defaults configured.',
              style: TextStyle(fontSize: 13),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: results
                  .map((result) => _AppResultTile(result: result))
                  .toList(),
            ),
    );
  }
}

class _AppResultTile extends StatelessWidget {
  const _AppResultTile({required this.result});

  final CompatibilityResult result;

  @override
  Widget build(BuildContext context) {
    final allOk = result.issues.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allOk ? LucideIcons.circleCheck : LucideIcons.circleAlert,
                size: 16,
                color: allOk ? Colors.green[600] : Colors.orange[700],
              ),
              const SizedBox(width: 8),
              Text(
                result.appName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              if (allOk)
                const Text(
                  'Fully compatible',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              else
                ShadBadge.outline(
                  child: Text(
                    '${result.issues.length} issue${result.issues.length > 1 ? 's' : ''}',
                  ),
                ),
            ],
          ),
          if (!allOk) ...[
            const SizedBox(height: 6),
            ...result.issues.map((issue) => _IssueTile(issue: issue)),
          ],
        ],
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue});

  final CompatibilityIssue issue;

  @override
  Widget build(BuildContext context) {
    final isError = issue.level == CompatibilityLevel.error;
    final icon = isError ? LucideIcons.circleX : LucideIcons.circleAlert;
    final color = isError ? Colors.red[700]! : Colors.orange[700]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.code,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(issue.message, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        SelectableText(
          text.isEmpty ? '(none)' : text,
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'Geist Mono',
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

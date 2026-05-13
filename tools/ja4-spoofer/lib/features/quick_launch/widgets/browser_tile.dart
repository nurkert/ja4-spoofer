import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/safe_network_icon.dart';
import '../../../app/widgets/terminal_box.dart';
import '../../../core/models/app_descriptor.dart';
import '../../../core/models/fingerprint_profile.dart';
import '../../app_launcher/app_launcher_controller.dart';

/// Generic app tile for the Quick Launch page.
///
/// Shows app icon, status, a single dynamic action button on the right,
/// and an optional output console.
class BrowserTile extends StatefulWidget {
  const BrowserTile({
    super.key,
    required this.app,
    required this.effectiveProfile,
    required this.onSmartLaunch,
    required this.onStop,
    this.showMoveToConfigurator = false,
    this.onMoveToConfigurator,
    this.onLaunchArgumentsChanged,
    this.onClearOutput,
  });

  final AppState app;
  final FingerprintProfile effectiveProfile;
  final void Function(AppState app) onSmartLaunch;
  final void Function(AppState app) onStop;

  final bool showMoveToConfigurator;
  final VoidCallback? onMoveToConfigurator;
  final void Function(AppState app, String value)? onLaunchArgumentsChanged;
  final void Function(AppState app)? onClearOutput;

  @override
  State<BrowserTile> createState() => _BrowserTileState();
}

class _BrowserTileState extends State<BrowserTile> {
  late final TextEditingController _argsController;

  @override
  void initState() {
    super.initState();
    _argsController = TextEditingController(text: widget.app.launchArguments);
  }

  @override
  void didUpdateWidget(covariant BrowserTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.app.launchArguments != _argsController.text) {
      _argsController.value = TextEditingValue(
        text: widget.app.launchArguments,
        selection: TextSelection.collapsed(
          offset: widget.app.launchArguments.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _argsController.dispose();
    super.dispose();
  }

  /// Dynamic label for the primary action button.
  String get _actionLabel {
    if (widget.app.isCli) {
      if (!widget.app.patched &&
          widget.app.buildState == AppBuildState.notBuilt) {
        return 'Patch, Build & Run';
      }
      if (widget.app.buildState == AppBuildState.notBuilt) {
        return 'Build & Run';
      }
      return 'Run';
    }
    if (!widget.app.patched &&
        widget.app.buildState == AppBuildState.notBuilt) {
      return 'Patch, Build & Launch';
    }
    if (widget.app.buildState == AppBuildState.notBuilt) {
      return 'Build & Launch';
    }
    return 'Launch';
  }

  IconData get _actionIcon {
    if (!widget.app.patched &&
        widget.app.buildState == AppBuildState.notBuilt) {
      return LucideIcons.hammer;
    }
    if (widget.app.buildState == AppBuildState.notBuilt) {
      return LucideIcons.hammer;
    }
    return widget.app.isCli ? LucideIcons.terminal : LucideIcons.play;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final desc = app.descriptor;
    final isRunning = app.buildState == AppBuildState.running;
    final isBuilding = app.buildState == AppBuildState.building;
    final isPatching = app.buildState == AppBuildState.patching;
    final isChecking = app.buildState == AppBuildState.checking;
    final isBusy = isBuilding || isPatching || isChecking;

    final statusColor = switch (app.buildState) {
      AppBuildState.built || AppBuildState.running => Colors.green,
      AppBuildState.notBuilt => Colors.orange,
      _ => Colors.grey,
    };

    final statusLabel = switch (app.buildState) {
      AppBuildState.checking => 'Checking...',
      AppBuildState.notBuilt => app.patched ? 'Not Built' : 'Not Patched',
      AppBuildState.patching => 'Patching...',
      AppBuildState.building => 'Building...',
      AppBuildState.built => 'Ready',
      AppBuildState.running => 'Running',
    };

    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SafeNetworkIcon(url: desc.metadata.iconUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      desc.metadata.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (desc.build.requirements.isNotEmpty &&
                            app.buildState == AppBuildState.notBuilt)
                          _RequirementsInfoButton(
                            requirements: desc.build.requirements,
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: statusColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (widget.showMoveToConfigurator)
                          Tooltip(
                            message:
                                'Move this rolled profile to the Configurator for editing & saving',
                            child: GestureDetector(
                              onTap: widget.onMoveToConfigurator,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.purple.withValues(alpha: 0.5),
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(
                                      LucideIcons.arrowUpRight,
                                      size: 11,
                                      color: Colors.purple,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'Move',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.purple,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (app.isCli) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ShadInput(
                    controller: _argsController,
                    onChanged: (value) =>
                        widget.onLaunchArgumentsChanged?.call(app, value),
                    placeholder: Text(
                      desc.launch.runtime.argsPlaceholder ?? 'https://..',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildActionButton(app, isBusy, isRunning),
              ] else ...[
                const SizedBox(width: 12),
                _buildActionButton(app, isBusy, isRunning),
              ],
            ],
          ),
          // Output console
          if (app.output.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Output',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (widget.onClearOutput != null)
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: () => widget.onClearOutput!(app),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TerminalBox(text: app.output, height: 120),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(AppState app, bool isBusy, bool isRunning) {
    if (isBusy) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isRunning) {
      return ShadButton.destructive(
        size: ShadButtonSize.sm,
        onPressed: () => widget.onStop(app),
        leading: const Icon(LucideIcons.square, size: 12),
        child: const Flexible(
          child: Text(
            'Stop',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      );
    }
    return ShadButton(
      size: ShadButtonSize.sm,
      onPressed: () => widget.onSmartLaunch(app),
      leading: Icon(_actionIcon, size: 12),
      child: Flexible(
        child: Text(
          _actionLabel,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

/// Small info button that shows build requirements in a dialog.
class _RequirementsInfoButton extends StatelessWidget {
  const _RequirementsInfoButton({required this.requirements});

  final List<BuildRequirement> requirements;

  void _showDialog(BuildContext context) {
    final visibleRequirements = requirements
        .where((r) => r.name.trim().isNotEmpty)
        .toList(growable: false);

    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text(
            'Build Requirements',
            style: TextStyle(fontSize: 15),
          ),
          content: SizedBox(
            width: 380,
            child: visibleRequirements.isEmpty
                ? const Text(
                    'No build requirements declared for this app.',
                    style: TextStyle(fontSize: 12),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: visibleRequirements
                          .map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '\u2022  ',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${r.name}${r.version != null ? ' ${r.version}' : ''}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (r.hint != null)
                                          SelectableText(
                                            r.hint!,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'Geist Mono',
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDialog(context),
      child: Tooltip(
        message: 'Build requirements',
        child: Icon(
          LucideIcons.info,
          size: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

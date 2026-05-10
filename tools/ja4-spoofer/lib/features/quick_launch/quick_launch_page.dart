import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/models/fingerprint_profile.dart';
import '../app_launcher/app_launcher_controller.dart';
import '../configurator/configurator_controller.dart';
import '../settings/settings_controller.dart';
import 'quick_launch_controller.dart';
import 'widgets/browser_tile.dart';
import 'widgets/configurator_preview_card.dart';
import 'widgets/profile_selector_card.dart';
import 'widgets/randomize_options_card.dart';

class QuickLaunchPage extends StatelessWidget {
  const QuickLaunchPage({
    super.key,
    required this.launcherController,
    required this.configuratorController,
    required this.settingsController,
    required this.onNavigateToConfigurator,
    this.quickLaunchController,
  });

  /// Shared controller provided by AppShell.
  final AppLauncherController launcherController;

  /// May be null while apps are still loading.
  final QuickLaunchController? quickLaunchController;

  final ConfiguratorController configuratorController;
  final SettingsController settingsController;

  /// Callback to navigate to the Configurator, optionally with a profile to load.
  final void Function([FingerprintProfile? profile]) onNavigateToConfigurator;

  @override
  Widget build(BuildContext context) {
    final qlc = quickLaunchController;

    // Show loader while QuickLaunchController is not yet available
    if (qlc == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        launcherController,
        qlc,
        configuratorController,
      ]),
      builder: (context, _) => _buildLayout(context, qlc),
    );
  }

  Widget _buildLayout(BuildContext context, QuickLaunchController qlc) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1100;

    if (isWide) {
      return _buildWideLayout(qlc);
    } else {
      return _buildNarrowLayout(qlc);
    }
  }

  Widget _buildWideLayout(QuickLaunchController qlc) {
    return Row(
      key: const ValueKey('wide'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 380,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildLeftColumn(qlc),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildRightColumn(qlc),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(QuickLaunchController qlc) {
    return SingleChildScrollView(
      key: const ValueKey('narrow'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLeftColumn(qlc),
          const SizedBox(height: 16),
          _buildRightColumn(qlc),
        ],
      ),
    );
  }

  Widget _buildLeftColumn(QuickLaunchController qlc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSelectorCard(
          controller: qlc,
          configuratorController: configuratorController,
          onNavigateToConfigurator: onNavigateToConfigurator,
        ),
        const SizedBox(height: 16),
        ConfiguratorPreviewCard(
          controller: configuratorController,
          quickLaunchController: qlc,
          onOpenConfigurator: () => onNavigateToConfigurator(),
        ),
        const SizedBox(height: 16),
        RandomizeOptionsCard(controller: qlc),
      ],
    );
  }

  Widget _buildRightColumn(QuickLaunchController qlc) {
    final lc = launcherController;

    final needsSetup =
        !lc.hasRepoRoot &&
        lc.apps.any((a) => a.buildState == AppBuildState.notBuilt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Apps',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (needsSetup)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ShadCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(LucideIcons.info, size: 16, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Runtime not configured',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Building requires a source checkout or packaged runtime with scripts, patches, and configs. '
                          'Check Settings if you use a custom source checkout.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (lc.loading)
          const Center(child: CircularProgressIndicator())
        else if (lc.apps.isEmpty)
          const ShadCard(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No apps found. Add YAML descriptors to assets/descriptors/ or ~/.ja4-spoofer/apps/',
                style: TextStyle(fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...lc.apps.map((app) {
            final profile = qlc.profileForLaunch(app);
            final randomActive =
                qlc.selectedSection == QuickLaunchSection.randomize;
            final hasRoll = qlc.hasRollFor(app.descriptor.appId);
            return Padding(
              key: ValueKey('tile-${app.descriptor.appId}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: BrowserTile(
                key: ValueKey('browser-${app.descriptor.appId}'),
                app: app,
                effectiveProfile: profile,
                showMoveToConfigurator: randomActive && hasRoll,
                onMoveToConfigurator: () =>
                    qlc.moveRollToConfigurator(app.descriptor.appId),
                onSmartLaunch: (a) {
                  unawaited(lc.smartLaunch(a, profile: profile));
                },
                onStop: (a) {
                  lc.stopApp(a);
                },
                onLaunchArgumentsChanged: (a, value) {
                  lc.updateLaunchArguments(a, value);
                },
                onClearOutput: (a) => lc.clearAppOutput(a),
              ),
            );
          }),
      ],
    );
  }
}

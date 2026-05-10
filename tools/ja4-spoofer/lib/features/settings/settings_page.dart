import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/widgets/section_card.dart';
import '../../core/models/app_settings.dart';
import 'settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.controller, this.onSaved});

  /// Shared controller provided by AppShell. Falls back to a local one if null.
  final SettingsController? controller;

  /// Called after settings are successfully persisted to disk.
  final VoidCallback? onSaved;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsController _controller;
  late final bool _ownsController;
  late final TextEditingController _repoPathCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = SettingsController();
      _ownsController = true;
    }
    _repoPathCtrl = TextEditingController();

    // Defer load() so its synchronous notifyListeners() doesn't fan out
    // a markNeedsBuild to SettingsScope ancestors mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.load().then((_) {
        if (mounted) _syncTextFields();
      });
    });
  }

  void _syncTextFields() {
    final s = _controller.settings;
    _repoPathCtrl.text = s.repoPath ?? '';
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    _repoPathCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory(TextEditingController ctrl) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null && mounted) {
      ctrl.text = result;
      await _save();
    }
  }

  Future<void> _save() async {
    await _controller.setRepoPath(_repoPathCtrl.text.trim());
    widget.onSaved?.call();
    if (mounted) {
      ShadSonner.of(
        context,
      ).show(const ShadToast(description: Text('Settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionCard(
                title: 'Settings',
                subtitle:
                    'Application-wide configuration. Directory picks save automatically; use the Save button for typed changes.',
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Source Checkout',
                subtitle:
                    'Optional path to a JA4 Spoofer source checkout. '
                    'Leave empty to use the packaged runtime automatically.',
                child: Row(
                  children: [
                    Expanded(
                      child: ShadInput(
                        controller: _repoPathCtrl,
                        placeholder: const Text(
                          'Packaged runtime (recommended)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ShadButton.outline(
                      onPressed: () => _pickDirectory(_repoPathCtrl),
                      child: const Text('Browse\u2026'),
                    ),
                    const SizedBox(width: 8),
                    ShadButton.ghost(
                      onPressed: () => _repoPathCtrl.clear(),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Privacy / Network',
                subtitle:
                    'Toggles for the only two places where this GUI talks to '
                    'the internet. Both are pure comfort — turn them off for '
                    'a fully offline experience.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 220,
                          child: ShadSelect<IanaSource>(
                            key: ValueKey(
                              'iana_source/${_controller.settings.ianaSource}',
                            ),
                            initialValue: _controller.settings.ianaSource,
                            onChanged: (next) async {
                              if (next == null) return;
                              await _controller.setIanaSource(next);
                              widget.onSaved?.call();
                            },
                            selectedOptionBuilder: (context, selected) =>
                                Text(_ianaSourceLabel(selected)),
                            options: const [
                              ShadOption<IanaSource>(
                                value: IanaSource.bundled,
                                child: Text('Bundled snapshot (offline)'),
                              ),
                              ShadOption<IanaSource>(
                                value: IanaSource.online,
                                child: Text('Online (iana.org)'),
                              ),
                              ShadOption<IanaSource>(
                                value: IanaSource.disabled,
                                child: Text('Disabled (hex only)'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'IANA registry source',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Bundled = parse the offline CSV snapshot '
                                'shipped under assets/iana/ (no network). '
                                'Online = fetch fresh CSVs from iana.org for '
                                'the latest names; falls back to bundled on '
                                'failure. Disabled = show hex IDs only and '
                                'never read the snapshot. Takes effect on '
                                'the next registry reload.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShadSwitch(
                          value: _controller.settings.loadRemoteIcons,
                          onChanged: (v) async {
                            await _controller.setLoadRemoteIcons(v);
                            widget.onSaved?.call();
                          },
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Load remote profile and app icons',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Off → no icon widget is rendered anywhere (no '
                                'placeholders, no HTTP request).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ShadButton(
                onPressed: _save,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.save, size: 14),
                    SizedBox(width: 6),
                    Text('Save'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _ianaSourceLabel(IanaSource source) {
  switch (source) {
    case IanaSource.bundled:
      return 'Bundled snapshot (offline)';
    case IanaSource.online:
      return 'Online (iana.org)';
    case IanaSource.disabled:
      return 'Disabled (hex only)';
  }
}

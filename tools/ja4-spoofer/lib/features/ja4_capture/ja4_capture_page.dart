import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/widgets/section_card.dart';
import '../../core/controllers/profile_catalog_controller.dart';
import '../../core/models/capture_record.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/models/registry_bundle.dart';
import 'ja4_capture_controller.dart';

class Ja4CapturePage extends StatefulWidget {
  const Ja4CapturePage({super.key, required this.profileCatalogController});

  final ProfileCatalogController profileCatalogController;

  @override
  State<Ja4CapturePage> createState() => _Ja4CapturePageState();
}

class _Ja4CapturePageState extends State<Ja4CapturePage> {
  late final Ja4CaptureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Ja4CaptureController(
      profileCatalogController: widget.profileCatalogController,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildServerCard(),
              const SizedBox(height: 16),
              _buildCaptureHistoryCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildServerCard() {
    final running = _controller.serverRunning;
    return SectionCard(
      title: 'TLS Capture',
      subtitle: 'Captures ClientHello fingerprints from any TLS client.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadButton.outline(
            onPressed: running
                ? () {
                    Clipboard.setData(
                      ClipboardData(
                        text: 'https://localhost:${_controller.port}',
                      ),
                    );
                  }
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.copy, size: 14),
                const SizedBox(width: 6),
                Text('https://localhost:${_controller.port}'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ShadButton(
            onPressed: () => unawaited(_controller.toggleServer()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(running ? LucideIcons.square : LucideIcons.play, size: 14),
                const SizedBox(width: 6),
                Text(running ? 'Stop' : 'Start'),
              ],
            ),
          ),
        ],
      ),
      child: const SizedBox.shrink(),
    );
  }

  Widget _buildCaptureHistoryCard() {
    final captures = _controller.captures.reversed.toList();
    return SectionCard(
      title: 'Capture History',
      subtitle: 'Recent TLS fingerprints captured from incoming connections.',
      trailing: ShadBadge.outline(child: Text('${captures.length} captures')),
      child: captures.isEmpty
          ? const Text('No captures yet.', style: TextStyle(fontSize: 13))
          : Column(
              children: captures.take(50).map((record) {
                return _CaptureRow(record: record, controller: _controller);
              }).toList(),
            ),
    );
  }
}

class _CaptureRow extends StatefulWidget {
  const _CaptureRow({required this.record, required this.controller});

  final CaptureRecord record;
  final Ja4CaptureController controller;

  @override
  State<_CaptureRow> createState() => _CaptureRowState();
}

class _CaptureRowState extends State<_CaptureRow> {
  bool _expanded = false;
  bool _saved = false;

  void _showSaveDialog() {
    final record = widget.record;
    final defaultName = record.sni != null
        ? 'Capture ${record.sni}'
        : 'Capture ${record.capturedAt.toIso8601String().substring(0, 19)}';
    final nameCtrl = TextEditingController(text: defaultName);
    final versionCtrl = TextEditingController();
    final iconUrlCtrl = TextEditingController();

    showShadDialog(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: const Text('Save Capture as Profile'),
        description: const Text(
          'Give this fingerprint a name to identify it later.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final version = versionCtrl.text.trim();
              final iconUrl = iconUrlCtrl.text.trim();
              unawaited(
                widget.controller.saveCapture(
                  record,
                  name: name,
                  version: version.isEmpty ? null : version,
                  iconUrl: iconUrl.isEmpty ? null : iconUrl,
                ),
              );
              Navigator.of(dialogContext).pop();
              setState(() => _saved = true);
            },
            child: const Text('Save'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text('Name', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            ShadInput(
              controller: nameCtrl,
              placeholder: const Text('e.g. Safari macOS'),
            ),
            const SizedBox(height: 12),
            const Text('Version', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            ShadInput(
              controller: versionCtrl,
              placeholder: const Text('e.g. 18.2'),
            ),
            const SizedBox(height: 12),
            const Text('Icon URL', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            ShadInput(
              controller: iconUrlCtrl,
              placeholder: const Text('https://example.com/logo.svg'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final time = record.capturedAt.toLocal();
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    final tls = record.tlsInputs;
    final detail = tls != null
        ? 'TLS ${tls.tlsMaxVersion} · '
              '${tls.cipherSuites.length} ciphers · '
              '${tls.extensions.length} exts · '
              '${tls.alpnProtocols.join(", ")}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ShadCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Expand/collapse toggle
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: tls != null
                      ? () => setState(() => _expanded = !_expanded)
                      : null,
                  child: Icon(
                    _expanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 14,
                  ),
                ),
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'Geist Mono',
                  ),
                ),
                if (record.count > 1) ...[
                  const SizedBox(width: 6),
                  ShadBadge.secondary(
                    child: Text(
                      'x${record.count}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
                if (record.sni != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    record.sni!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
                if (record.sourceAddress != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    record.sourceAddress!,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
                const Spacer(),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: record.ja4Hash),
                    );
                  },
                  child: const Icon(LucideIcons.copy, size: 12),
                ),
                _saved
                    ? const ShadBadge.secondary(child: Text('Saved'))
                    : ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: _showSaveDialog,
                        child: const Text('Save'),
                      ),
              ],
            ),
            const SizedBox(height: 4),
            // JA4 hash
            Text(
              record.ja4Hash,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'Geist Mono',
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            // Expanded detail view
            if (_expanded && tls != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _TlsDetailView(
                inputs: tls,
                registry: widget.controller.showIanaNames
                    ? widget.controller.registry
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Displays all captured TLS ClientHello fields.
class _TlsDetailView extends StatelessWidget {
  const _TlsDetailView({required this.inputs, this.registry});

  final TlsClientHelloInputs inputs;
  final RegistryBundle? registry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldRow(
          'TLS Version',
          '${inputs.tlsMinVersion} – ${inputs.tlsMaxVersion}',
        ),
        _fieldRow('SNI Mode', inputs.sniMode),
        _fieldRow(
          'ALPN',
          inputs.alpnProtocols.isEmpty
              ? '(none)'
              : inputs.alpnProtocols.join(', '),
        ),
        _fieldRow('GREASE', inputs.enableGrease ? 'enabled' : 'disabled'),
        _fieldRow(
          'CH Ext Permutation',
          inputs.enableChXtnPermutation ? 'enabled' : 'disabled',
        ),
        const SizedBox(height: 8),
        _idListSection(
          'Cipher Suites (${inputs.cipherSuites.length})',
          inputs.cipherSuites,
          registry?.cipherSuites,
        ),
        const SizedBox(height: 8),
        _idListSection(
          'Extensions (${inputs.extensions.length})',
          inputs.extensions,
          registry?.extensions,
        ),
        const SizedBox(height: 8),
        _idListSection(
          'Signature Algorithms (${inputs.signatureAlgorithms.length})',
          inputs.signatureAlgorithms,
          registry?.signatureSchemes,
        ),
      ],
    );
  }

  Widget _fieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontFamily: 'Geist Mono'),
            ),
          ),
        ],
      ),
    );
  }

  String _resolve(int id, List<dynamic>? items) {
    final hex = '0x${id.toRadixString(16).padLeft(4, '0')}';
    if (items == null) return hex;
    for (final item in items) {
      if (item.id == id) return '$hex  ${item.name}';
    }
    return hex;
  }

  Widget _idListSection(String title, List<int> values, List<dynamic>? items) {
    final useNames = items != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        if (values.isEmpty)
          const Text(
            '(none)',
            style: TextStyle(fontSize: 10, fontFamily: 'Geist Mono'),
          )
        else if (useNames)
          // One line per entry with IANA name
          ...values.map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(
                _resolve(v, items),
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'Geist Mono',
                  height: 1.5,
                ),
              ),
            ),
          )
        else
          // Compact comma-separated hex list
          Text(
            values
                .map((v) => '0x${v.toRadixString(16).padLeft(4, '0')}')
                .join(', '),
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'Geist Mono',
              height: 1.5,
            ),
          ),
      ],
    );
  }
}

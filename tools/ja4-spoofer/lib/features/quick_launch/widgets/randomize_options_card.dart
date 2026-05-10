import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/section_card.dart';
import '../../../core/utils/random_engine.dart';
import '../quick_launch_controller.dart';

class RandomizeOptionsCard extends StatefulWidget {
  const RandomizeOptionsCard({super.key, required this.controller});

  final QuickLaunchController controller;

  @override
  State<RandomizeOptionsCard> createState() => _RandomizeOptionsCardState();
}

class _RandomizeOptionsCardState extends State<RandomizeOptionsCard> {
  bool _customExpanded = false;

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final isSelected = ctrl.selectedSection == QuickLaunchSection.randomize;

    return SectionCard(
      title: 'Randomize',
      subtitle:
          'Per-app fresh ClientHellos — settings change re-roll instantly.',
      isSelected: isSelected,
      onTap: () => ctrl.selectSection(QuickLaunchSection.randomize),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SeedRow(controller: ctrl),
          const SizedBox(height: 12),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => setState(() => _customExpanded = !_customExpanded),
            leading: Icon(
              _customExpanded
                  ? LucideIcons.chevronDown
                  : LucideIcons.chevronRight,
              size: 13,
            ),
            child: const Text('Custom', style: TextStyle(fontSize: 12)),
          ),
          if (_customExpanded) ...[
            const SizedBox(height: 10),
            _CustomPanel(controller: ctrl),
          ],
        ],
      ),
    );
  }
}

class _SeedRow extends StatefulWidget {
  const _SeedRow({required this.controller});
  final QuickLaunchController controller;

  @override
  State<_SeedRow> createState() => _SeedRowState();
}

class _SeedRowState extends State<_SeedRow> {
  late final TextEditingController _seedField;

  @override
  void initState() {
    super.initState();
    _seedField = TextEditingController(text: widget.controller.masterSeed);
    widget.controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _seedField.dispose();
    super.dispose();
  }

  void _syncFromController() {
    if (_seedField.text != widget.controller.masterSeed) {
      _seedField.text = widget.controller.masterSeed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Icon(
          LucideIcons.hash,
          size: 12,
          color: theme.colorScheme.mutedForeground,
        ),
        const SizedBox(width: 6),
        Text(
          'seed:',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ShadInput(
            controller: _seedField,
            placeholder: const Text('random'),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(64),
            ],
            onChanged: (value) {
              if (value.trim() != widget.controller.masterSeed) {
                widget.controller.setSeed(value);
              }
            },
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: theme.colorScheme.foreground,
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(LucideIcons.refreshCw, size: 13),
          tooltip: 'Generate fresh random seed',
          onPressed: () => widget.controller.randomizeSeed(),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
      ],
    );
  }
}

class _CustomPanel extends StatelessWidget {
  const _CustomPanel({required this.controller});
  final QuickLaunchController controller;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            const SizedBox(width: 80),
            Expanded(
              flex: 2,
              child: Tooltip(
                message:
                    'Pool = the source of IDs that Swap (S) and Append-junk (J) draw from.\n\n'
                    'Background: a TLS ClientHello is an offer list, not a requirement.\n'
                    'The server picks what it likes and ignores everything else.\n'
                    'So adding extra IDs to the offer does not break the connection —\n'
                    'the server simply selects the same cipher/extension it would have anyway.\n\n'
                    'constrained — only the IDs this app already uses in its own ClientHello.\n'
                    '              Swap becomes a no-op (nothing new to swap in).\n\n'
                    'mixed       — app defaults + extra IDs from other real browsers\n'
                    '              (Chrome, Firefox, Safari). Servers encounter these\n'
                    '              routinely and handle them without issues.\n'
                    '              Best balance: different fingerprint, same connectivity.\n\n'
                    'chaos       — completely random 16-bit IDs. Servers may reject\n'
                    '              codes they have never seen → expect failures.',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pool',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      LucideIcons.info,
                      size: 10,
                      color: theme.colorScheme.mutedForeground.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Tooltip(
                message:
                    'Which part of the JA4 fingerprint each mutation affects:\n\n'
                    'P — Permute  : only available for SigAlg.\n'
                    '               JA4 sorts ciphers and extensions before hashing,\n'
                    '               so P would have zero effect there.\n'
                    '               Sig-algs are hashed in wire order → P changes JA4_c.\n\n'
                    'S — Swap     : replaces non-mandatory IDs with pool alternatives.\n'
                    '               Count stays the same → changes JA4_b / JA4_c.\n\n'
                    'D — Drop     : removes non-mandatory IDs. Count decreases.\n'
                    '               → changes JA4_a  (cipher / extension count)\n\n'
                    'J — Junk     : appends extra IDs from the pool. Count increases.\n'
                    '               → changes JA4_a  (cipher / extension count)\n\n'
                    'Tip: to vary JA4_a, enable D or J on Cipher and/or Extension.',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mutations',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      LucideIcons.info,
                      size: 10,
                      color: theme.colorScheme.mutedForeground.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final c in RandomComponent.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ComponentRow(controller: controller, component: c),
          ),
        const SizedBox(height: 10),
        _Ja4aSection(controller: controller),
        const SizedBox(height: 8),
        Tooltip(
          message:
              'By default, a fixed set of IDs is always kept in the list\n'
              'so the TLS handshake never breaks:\n\n'
              '  Ciphers    : TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384,\n'
              '               TLS_CHACHA20_POLY1305_SHA256\n'
              '  Extensions : SNI (0), supported_groups (10),\n'
              '               signature_algorithms (13), supported_versions (43),\n'
              '               psk_key_exchange_modes (45), key_share (51)\n'
              '  SigAlgs    : ecdsa_secp256r1_sha256, rsa_pss_rsae_sha256\n\n'
              'Enabling this lets Drop and Swap touch those IDs too.\n'
              'Useful for maximum fingerprint variation,\n'
              'but may cause handshake failures on strict servers.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadCheckbox(
                value: controller.randomConfig.allowIncompat,
                onChanged: (v) => controller.setAllowIncompat(v),
                label: const Text(
                  'Relax safety pins',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.info,
                size: 10,
                color: theme.colorScheme.mutedForeground.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.controller, required this.component});
  final QuickLaunchController controller;
  final RandomComponent component;

  @override
  Widget build(BuildContext context) {
    final cfg = controller.randomConfig.forComponent(component);
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            _label(component),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          flex: 2,
          child: ShadSelect<RandomPool>(
            key: ValueKey('pool-${component.name}-${cfg.pool.name}'),
            initialValue: cfg.pool,
            onChanged: (v) {
              if (v != null) {
                controller.setComponentPool(component, v);
              }
            },
            selectedOptionBuilder: (ctx, v) =>
                Text(_poolLabel(v), style: const TextStyle(fontSize: 11)),
            options: [
              for (final p in RandomPool.values)
                ShadOption<RandomPool>(
                  value: p,
                  child: _PoolOptionContent(pool: p),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final m in _availableMutations(component))
                _MutationChip(
                  label: _mutationShort(m),
                  tooltip: _mutationTooltip(m, cfg.pool),
                  selected: cfg.mutations.contains(m),
                  disabled: _isNoOp(m, cfg.pool),
                  onTap: () => controller.toggleMutation(component, m),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // P has no JA4 effect for Cipher/Extension (JA4 sorts them before hashing).
  // Only SigAlg wire order is preserved in JA4_c, so P is meaningful there.
  static List<MutationType> _availableMutations(RandomComponent c) =>
      c == RandomComponent.sigalg
      ? MutationType.values
      : MutationType.values.where((m) => m != MutationType.permute).toList();

  // S and J are no-ops when pool=constrained (no foreign IDs to draw from).
  static bool _isNoOp(MutationType m, RandomPool pool) =>
      pool == RandomPool.constrained &&
      (m == MutationType.swap || m == MutationType.appendJunk);

  static String _label(RandomComponent c) => switch (c) {
    RandomComponent.cipher => 'Cipher',
    RandomComponent.extension => 'Extension',
    RandomComponent.sigalg => 'Sigalg',
  };

  static String _poolLabel(RandomPool p) => switch (p) {
    RandomPool.constrained => 'constrained',
    RandomPool.mixed => 'mixed',
    RandomPool.chaos => 'chaos',
  };

  static String _mutationShort(MutationType m) => switch (m) {
    MutationType.permute => 'P',
    MutationType.drop => 'D',
    MutationType.swap => 'S',
    MutationType.appendJunk => 'J',
  };

  static String _mutationTooltip(MutationType m, RandomPool pool) {
    final noOpNote =
        (m == MutationType.swap || m == MutationType.appendJunk) &&
            pool == RandomPool.constrained
        ? '\n⚠ No-op with constrained pool — switch to mixed to enable.'
        : '';
    return switch (m) {
      MutationType.permute =>
        'Permute — shuffles the wire order of IDs.\n'
            'Cipher and Extension: no JA4 fingerprint change — JA4 sorts\n'
            'these before hashing, so any wire order yields the same hash.\n'
            'SigAlg: changes JA4_c — sig-algs are hashed in wire order.\n'
            'Combine with S to also vary which IDs appear.',
      MutationType.swap =>
        'Swap — replaces non-mandatory IDs with alternatives from the pool.\n'
            'Count stays the same → JA4_a unchanged, JA4_b/c change.\n'
            'With mixed pool: substitutes known IANA IDs that servers safely ignore.$noOpNote',
      MutationType.drop =>
        'Drop — removes up to N non-mandatory IDs.\n'
            'Count decreases → JA4_a cipher/extension count changes.\n'
            'Mandatory IDs (TLS 1.3 ciphers, key_share, SNI…) are never dropped.',
      MutationType.appendJunk =>
        'Append-junk — adds N extra IDs from the pool at the end.\n'
            'Count increases → JA4_a cipher/extension count changes.$noOpNote',
    };
  }
}

class _MutationChip extends StatelessWidget {
  const _MutationChip({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.warn = false,
    this.disabled = false,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  /// When true and selected, renders in amber (risky option warning).
  final bool warn;

  /// When true, renders greyed out and ignores taps (no-op in current config).
  final bool disabled;

  static const _amber = Color(0xFFB45309);
  static const _amberBg = Color(0xFFFEF3C7);

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isWarnActive = warn && selected;

    Color bgColor;
    Color borderColor;
    Color textColor;

    if (disabled) {
      bgColor = theme.colorScheme.muted.withValues(alpha: 0.2);
      borderColor = theme.colorScheme.border.withValues(alpha: 0.25);
      textColor = theme.colorScheme.foreground.withValues(alpha: 0.3);
    } else if (isWarnActive) {
      bgColor = _amberBg.withValues(alpha: 0.5);
      borderColor = _amber.withValues(alpha: 0.6);
      textColor = _amber;
    } else if (selected) {
      bgColor = theme.colorScheme.primary.withValues(alpha: 0.16);
      borderColor = theme.colorScheme.primary.withValues(alpha: 0.6);
      textColor = theme.colorScheme.primary;
    } else {
      bgColor = theme.colorScheme.muted.withValues(alpha: 0.4);
      borderColor = theme.colorScheme.border.withValues(alpha: 0.5);
      textColor = theme.colorScheme.foreground.withValues(alpha: 0.65);
    }

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// JA4_a section
// ---------------------------------------------------------------------------

extension _AlpnModeUi on AlpnMode {
  String get label => switch (this) {
    AlpnMode.keep => 'keep',
    AlpnMode.random => 'random',
  };

  String get tooltip => switch (this) {
    AlpnMode.keep =>
      'Use the app\'s default ALPN list unchanged.\n'
          'Typical: [h2, http/1.1]. JA4_a encodes the first\n'
          'and last ALPN protocol — "keep" means no JA4_a change here.',
    AlpnMode.random =>
      'Randomly pick one of: [h2, http/1.1], [h2], [http/1.1],\n'
          'or [h2, http/1.1, h3-29] — different per roll (deterministic with seed).\n'
          'Directly changes the ALPN field in JA4_a.',
  };
}

extension _TlsVersionModeUi on TlsVersionMode {
  String get label => switch (this) {
    TlsVersionMode.v12and13 => '1.2 + 1.3',
    TlsVersionMode.v13only => '1.3',
    TlsVersionMode.v12only => '1.2',
    TlsVersionMode.random => 'random',
  };

  String get tooltip => switch (this) {
    TlsVersionMode.v12and13 =>
      'Offer TLS 1.2 and 1.3 — what most real browsers do.\n'
          'JA4_a shows \'13\' (highest offered version).\n'
          'Server picks 1.3 if supported, falls back to 1.2 otherwise.',
    TlsVersionMode.v13only =>
      'Offer only TLS 1.3 — modern TLS-1.3-only client appearance.\n'
          'JA4_a shows \'13\'.\n'
          'Servers without TLS 1.3 support will reject the connection.',
    TlsVersionMode.v12only =>
      'Offer only TLS 1.2 — looks like an older client.\n'
          'JA4_a shows \'12\' instead of \'13\' — this changes JA4_a directly.\n'
          'Most servers still support 1.2; connection is generally safe.',
    TlsVersionMode.random =>
      'Pick one of the three options randomly per roll.\n'
          'Result is deterministic for a given seed (uses subSeedBytes[9] % 3).\n'
          'JA4_a version field varies between \'12\' and \'13\' across rolls.',
  };
}

extension _SniModeUi on SniRandomMode {
  String get label => switch (this) {
    SniRandomMode.present => 'present',
    SniRandomMode.random => 'random',
    SniRandomMode.none => 'none',
  };

  String get tooltip => switch (this) {
    SniRandomMode.present =>
      'Always send the server hostname (SNI) in the ClientHello.\n'
          'JA4_a shows \'d\'. Required for most HTTPS sites — servers\n'
          'use SNI to route requests to the correct virtual host.',
    SniRandomMode.random =>
      'Per-roll coin flip: sometimes present (\'d\'), sometimes absent (\'i\').\n'
          'Result is deterministic for a given seed.\n'
          'Roughly half of connections to shared-hosting HTTPS sites will fail.',
    SniRandomMode.none =>
      'Never send SNI. JA4_a shows \'i\'.\n'
          'Most HTTPS sites on shared hosting will refuse the connection.\n'
          'Only works for servers with a dedicated IP and no virtual hosting.',
  };
}

class _Ja4aSection extends StatelessWidget {
  const _Ja4aSection({required this.controller});
  final QuickLaunchController controller;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final cfg = controller.randomConfig;
    final labelStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.foreground,
    );
    final mutedStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.mutedForeground,
    );

    final anyDrop = RandomComponent.values.any(
      (c) => cfg.forComponent(c).mutations.contains(MutationType.drop),
    );
    final anyJunk = RandomComponent.values.any(
      (c) => cfg.forComponent(c).mutations.contains(MutationType.appendJunk),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Text('JA4_a', style: mutedStyle),
            const SizedBox(width: 6),
            Expanded(
              child: Divider(
                color: theme.colorScheme.border.withValues(alpha: 0.4),
                thickness: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // SNI row
        Tooltip(
          message:
              'SNI (Server Name Indication) is the hostname field in the\n'
              'TLS ClientHello. JA4_a encodes its presence as \'d\' or absence\n'
              'as \'i\' — toggling this directly changes JA4_a.',
          child: Row(
            children: [
              SizedBox(width: 80, child: Text('SNI', style: labelStyle)),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final mode in SniRandomMode.values)
                      _MutationChip(
                        label: mode.label,
                        tooltip: mode.tooltip,
                        selected: cfg.sniMode == mode,
                        warn: mode != SniRandomMode.present,
                        onTap: () => controller.setSniMode(mode),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // TLS version row
        const SizedBox(height: 6),
        Tooltip(
          message:
              'Which TLS versions to offer in the ClientHello.\n'
              '\'1.2\' changes JA4_a directly — version field becomes \'12\'.\n'
              '\'random\' picks one of the three options per roll (deterministic with seed).',
          child: Row(
            children: [
              SizedBox(width: 80, child: Text('TLS', style: labelStyle)),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final mode in TlsVersionMode.values)
                      _MutationChip(
                        label: mode.label,
                        tooltip: mode.tooltip,
                        selected: cfg.tlsVersionMode == mode,
                        onTap: () => controller.setTlsVersionMode(mode),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ALPN row
        const SizedBox(height: 6),
        Tooltip(
          message:
              'ALPN (Application-Layer Protocol Negotiation) tells the server\n'
              'which protocols the client supports (e.g. h2, http/1.1, h3-29).\n'
              'JA4_a encodes the first and last ALPN protocol — randomizing this\n'
              'changes JA4_a directly. Servers pick from the offered list safely.',
          child: Row(
            children: [
              SizedBox(width: 80, child: Text('ALPN', style: labelStyle)),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final mode in AlpnMode.values)
                      _MutationChip(
                        label: mode.label,
                        tooltip: mode.tooltip,
                        selected: cfg.alpnMode == mode,
                        onTap: () => controller.setAlpnMode(mode),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Count amounts row — only shown when D or J active on any component
        if (anyDrop || anyJunk) ...[
          const SizedBox(height: 6),
          Tooltip(
            message:
                'These caps control how many IDs are removed (D) or appended (J)\n'
                'per roll. The actual count is random up to this maximum.\n'
                'Both directly alter the cipher and extension count in JA4_a.',
            child: Row(
              children: [
                SizedBox(width: 80, child: Text('Count', style: labelStyle)),
                if (anyDrop) ...[
                  Text(
                    'drop ≤',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _AmountField(
                    value: cfg.dropAmount,
                    onChanged: controller.setDropAmount,
                  ),
                ],
                if (anyDrop && anyJunk) const SizedBox(width: 12),
                if (anyJunk) ...[
                  Text(
                    'junk ≤',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _AmountField(
                    value: cfg.junkAmount,
                    onChanged: controller.setJunkAmount,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AmountField extends StatefulWidget {
  const _AmountField({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(_AmountField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      final t = '${widget.value}';
      if (_ctrl.text != t) _ctrl.text = t;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: ShadInput(
        controller: _ctrl,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null && n >= 1) widget.onChanged(n);
        },
        style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PoolOptionContent extends StatelessWidget {
  const _PoolOptionContent({required this.pool});
  final RandomPool pool;

  static const _descriptions = {
    RandomPool.constrained:
        'Only this app\'s own TLS defaults — Swap is a no-op here.',
    RandomPool.mixed:
        'App defaults + IDs from other real browsers — server picks, ignores the rest.',
    RandomPool.chaos:
        'Random 16-bit IDs — maximum drift, likely breaks connections.',
  };

  static const _labels = {
    RandomPool.constrained: 'constrained',
    RandomPool.mixed: 'mixed',
    RandomPool.chaos: 'chaos',
  };

  static const _dangerColor = Color(0xFFB91C1C);

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isChaos = pool == RandomPool.chaos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isChaos) ...[
              const Icon(
                LucideIcons.triangleAlert,
                size: 10,
                color: _dangerColor,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              _labels[pool]!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isChaos ? _dangerColor : null,
              ),
            ),
          ],
        ),
        Text(
          _descriptions[pool]!,
          style: TextStyle(
            fontSize: 10,
            color: isChaos
                ? _dangerColor.withValues(alpha: 0.75)
                : theme.colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }
}

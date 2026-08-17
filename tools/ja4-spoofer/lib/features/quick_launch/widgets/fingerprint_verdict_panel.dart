import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/utils/fingerprint_enforcement.dart';
import '../../../core/utils/ja4_dump_verifier.dart';

/// Colours for the three enforcement severities and the launch verdict.
class _VerdictColors {
  const _VerdictColors._();

  static const blocker = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);
  static const info = Color(0xFF6B7280);
  static const ok = Color(0xFF16A34A);
}

Color _severityColor(EnforcementSeverity severity) => switch (severity) {
  EnforcementSeverity.blocker => _VerdictColors.blocker,
  EnforcementSeverity.warning => _VerdictColors.warning,
  EnforcementSeverity.info => _VerdictColors.info,
};

IconData _severityIcon(EnforcementSeverity severity) => switch (severity) {
  EnforcementSeverity.blocker => LucideIcons.circleAlert,
  EnforcementSeverity.warning => LucideIcons.triangleAlert,
  EnforcementSeverity.info => LucideIcons.info,
};

/// Compact, always-visible answer to "wird der Fingerprint, den ich gewählt
/// habe, auch gesendet?".
///
/// Before a launch it shows the pre-flight verdict for the selected profile;
/// after a launch it shows what the patched library reports it actually put on
/// the wire. Both states carry the JA4 so the two values can be compared at a
/// glance.
class FingerprintVerdictPanel extends StatelessWidget {
  const FingerprintVerdictPanel({
    super.key,
    required this.enforcement,
    required this.verdict,
    this.isRunning = false,
  });

  final EnforcementReport? enforcement;
  final DumpVerdict? verdict;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final report = enforcement;
    if (report == null) return const SizedBox.shrink();

    // A finished launch outranks the pre-flight prediction: it is a
    // measurement rather than a forecast.
    if (verdict != null) {
      return _VerdictBanner(verdict: verdict!, report: report);
    }
    if (isRunning) {
      return _Banner(
        color: _VerdictColors.info,
        icon: LucideIcons.loaderCircle,
        title: 'Warte auf den ersten ClientHello …',
        subtitle:
            'Sobald die Anwendung eine TLS-Verbindung aufbaut, wird der '
            'gesendete Fingerprint hier gegen ${report.intendedJa4} geprüft.',
      );
    }
    return _PreflightSummary(report: report);
  }
}

class _PreflightSummary extends StatelessWidget {
  const _PreflightSummary({required this.report});

  final EnforcementReport report;

  @override
  Widget build(BuildContext context) {
    final blockers = report.blockers.length;
    final warnings = report.warnings.length;

    final (color, icon, title) = switch (blockers) {
      0 when warnings == 0 => (
        _VerdictColors.ok,
        LucideIcons.shieldCheck,
        'Profil ist so umsetzbar',
      ),
      0 => (
        _VerdictColors.warning,
        LucideIcons.triangleAlert,
        '$warnings Einschränkung(en) auf dieser Library',
      ),
      _ => (
        _VerdictColors.blocker,
        LucideIcons.circleAlert,
        '$blockers Abweichung(en) — so wird ein anderer Fingerprint gesendet',
      ),
    };

    return _Banner(
      color: color,
      icon: icon,
      title: title,
      subtitle: 'Ziel-JA4: ${report.intendedJa4}',
      details: report.issues.isEmpty ? null : _IssueList(issues: report.issues),
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.verdict, required this.report});

  final DumpVerdict verdict;
  final EnforcementReport report;

  @override
  Widget build(BuildContext context) {
    final ok = verdict.matches;
    final partial = !ok && verdict.ja4Matches;
    final color = ok
        ? _VerdictColors.ok
        : (partial ? _VerdictColors.warning : _VerdictColors.blocker);
    final icon = ok
        ? LucideIcons.shieldCheck
        : (partial ? LucideIcons.triangleAlert : LucideIcons.shieldX);

    return _Banner(
      color: color,
      icon: icon,
      title: verdict.headline,
      subtitle: _subtitle(),
      details: _Details(verdict: verdict),
    );
  }

  String _subtitle() {
    final intended = verdict.intendedJa4;
    final effective = verdict.effectiveJa4;
    if (intended == null) return '';
    if (effective == null) return 'Ausgewählt: $intended';
    if (intended == effective) return 'Gesendet: $effective';
    return 'Ausgewählt: $intended\nGesendet:   $effective';
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.verdict});

  final DumpVerdict verdict;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final reason in verdict.maskReasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(reason, style: const TextStyle(fontSize: 12)),
          ),
        for (final deviation in verdict.deviations)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviation.field,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'angefordert: ${deviation.requested}',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
                Text(
                  'gesendet:    ${deviation.actual}',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
                Text(
                  deviation.reason,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({required this.issues});

  final List<EnforcementIssue> issues;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: EnforcementIssueView(issue: issue),
          ),
      ],
    );
  }
}

/// One issue rendered as what / why / how-to-fix — the three things a user
/// needs to decide whether the launch is still worth doing.
class EnforcementIssueView extends StatelessWidget {
  const EnforcementIssueView({super.key, required this.issue});

  final EnforcementIssue issue;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(issue.severity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_severityIcon(issue.severity), size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                issue.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            _Chip(text: issue.field),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Line(label: 'Abweichung', value: issue.deviation),
              _Line(label: 'Ursache', value: issue.reason),
              _Line(label: 'Lösung', value: issue.remedy),
            ],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 11.5),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
      ),
    );
  }
}

class _Banner extends StatefulWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.details,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? details;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.08),
        border: Border.all(color: widget.color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 15, color: widget.color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: widget.color,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.details != null)
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Weniger' : 'Details'),
                ),
            ],
          ),
          if (_expanded && widget.details != null) ...[
            const SizedBox(height: 10),
            widget.details!,
          ],
        ],
      ),
    );
  }
}

/// What the user chose in the pre-flight dialog.
enum EnforcementDecision { cancel, autoFix, launchAnyway }

/// Shows the blocking pre-flight dialog and returns the user's decision.
///
/// The launch is held back rather than silently proceeding, because a run
/// against a fingerprint the stack rewrote produces a measurement that looks
/// valid and is not.
Future<EnforcementDecision> showEnforcementDialog(
  BuildContext context,
  EnforcementReport report,
) async {
  final decision = await showShadDialog<EnforcementDecision>(
    context: context,
    builder: (context) => ShadDialog.alert(
      title: const Text('Dieser Fingerprint würde so nicht gesendet'),
      description: Text(
        'Ziel-JA4: ${report.intendedJa4}\n'
        'Auf ${report.stack?.displayName ?? 'diesem Ziel'} würde der '
        'ClientHello davon abweichen:',
      ),
      constraints: const BoxConstraints(maxWidth: 640),
      actions: [
        ShadButton.outline(
          onPressed: () =>
              Navigator.of(context).pop(EnforcementDecision.cancel),
          child: const Text('Abbrechen'),
        ),
        ShadButton.secondary(
          onPressed: () =>
              Navigator.of(context).pop(EnforcementDecision.launchAnyway),
          child: const Text('Trotzdem starten'),
        ),
        if (report.hasAutoFixes)
          ShadButton(
            onPressed: () =>
                Navigator.of(context).pop(EnforcementDecision.autoFix),
            child: const Text('Beheben & starten'),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final issue in report.blockers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: EnforcementIssueView(issue: issue),
                ),
              for (final issue in report.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: EnforcementIssueView(issue: issue),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  return decision ?? EnforcementDecision.cancel;
}

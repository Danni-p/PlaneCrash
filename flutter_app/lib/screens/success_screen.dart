import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/weather_inputs.dart';
import '../utils/labels.dart';

/// Shown when the run ends (altitude reached 0). The headline metric is how
/// close the plane reached the island; there is no lose state.
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({
    super.key,
    required this.distanceToIsland,
    required this.peakLeft,
    required this.peakRight,
    required this.weatherAtEnd,
    required this.durationSeconds,
  });

  final int distanceToIsland;
  final int peakLeft;
  final int peakRight;
  final WeatherInputs weatherAtEnd;
  final int durationSeconds;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final perfect = widget.distanceToIsland <= 0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    perfect ? Icons.beach_access : Icons.sailing,
                    size: 88,
                    color: const Color(0xFF39FF14),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.successTitle,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    perfect
                        ? l10n.successPerfect
                        : l10n.successDistance(widget.distanceToIsland),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: const Color(0xFF39FF14),
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (!perfect) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.successSwimHint,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  _StatRow(
                    label: l10n.successPeakCrew,
                    value: '${widget.peakLeft + widget.peakRight} '
                        '(${widget.peakLeft} / ${widget.peakRight})',
                  ),
                  _StatRow(
                    label: l10n.successWeatherAtEnd,
                    value: Labels.weatherSummary(l10n, widget.weatherAtEnd),
                  ),
                  _StatRow(
                    label: l10n.successDuration,
                    value: l10n.successDurationValue(widget.durationSeconds),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context)
                          .popUntil((route) => route.isFirst),
                      icon: const Icon(Icons.home),
                      label: Text(l10n.successBackHome),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

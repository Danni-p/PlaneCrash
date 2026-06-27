import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart';

/// Where the island distance label is anchored relative to the scenery.
enum IslandViewportMode {
  onIsland,
  offScreenLeft,
  offScreenRight,
}

/// Size of the target island landmass on the horizon.
class IslandLandMetrics {
  const IslandLandMetrics({
    required this.width,
    required this.height,
    required this.peakY,
  });

  final double width;
  final double height;
  final double peakY;
}

/// Shared geometry for the target island, edge arrows, and distance overlay.
abstract final class IslandViewportLayout {
  static const double halfFovRad = 55 * math.pi / 180;
  static const double horizonFractionAtHighAltitude = 0.85;
  static const double horizonFractionAtLowAltitude = 0.22;
  static const double arrowMargin = 18.0;
  static const double arrowHalfHeight = 26.0;
  static const double arrowDepth = 28.0;
  static const double labelPadding = 12.0;
  static const double labelEstimatedHeight = 34.0;
  static const double labelTopInset = 8.0;
  static const double arrowLabelGap = 8.0;

  /// Normalized distance floor for inverse visual scaling (100 m at 10 km spawn).
  static const double minVisualDistanceRatio = 0.01;

  /// Maps straight-line distance to a 0..1 visual approach progress using
  /// inverse-distance perspective: slow growth while far, rapid growth when close.
  /// Gameplay distance and score are unchanged; only island size uses this value.
  static double visualApproachFromDistance({
    required double distanceMeters,
    required double initialDistance,
    double minDistanceRatio = minVisualDistanceRatio,
  }) {
    if (initialDistance <= 0) return 0.0;
    final r = (distanceMeters / initialDistance).clamp(minDistanceRatio, 1.0);
    final inv = 1 / r;
    final invMin = 1 / minDistanceRatio;
    return ((inv - 1) / (invMin - 1)).clamp(0.0, 1.0);
  }

  static double horizonFractionForAltitude(
    double altitude, {
    required double referenceAltitude,
  }) {
    if (referenceAltitude <= 0) return horizonFractionAtLowAltitude;
    final t = (1 - altitude / referenceAltitude).clamp(0.0, 1.0);
    final eased = Curves.easeInOut.transform(t);
    return lerpDouble(
          horizonFractionAtHighAltitude,
          horizonFractionAtLowAltitude,
          eased,
        ) ??
        horizonFractionAtHighAltitude;
  }

  static double horizonYFor(
    Size size, {
    required double altitude,
    required double referenceAltitude,
  }) =>
      size.height *
      horizonFractionForAltitude(
        altitude,
        referenceAltitude: referenceAltitude,
      );

  static IslandLandMetrics landMetrics({
    required Size size,
    required double progress,
    required double scale,
    required double horizonY,
  }) {
    final t = progress.clamp(0.0, 1.0);
    final width = size.width * (0.18 + 0.55 * t) * scale;
    final height = size.height * (0.05 + 0.22 * t) * scale;
    return IslandLandMetrics(
      width: width,
      height: height,
      peakY: horizonY - height * 0.9,
    );
  }

  static bool isOffScreen(double relativeBearing) =>
      relativeBearing.abs() > halfFovRad;

  static double islandCenterX(Size size, double relativeBearing) =>
      size.width / 2 + (relativeBearing / halfFovRad) * (size.width / 2);

  static double arrowTipX(Size size, {required bool toRight}) =>
      toRight ? size.width - arrowMargin : arrowMargin;

  static double arrowBaseX(double tipX, {required bool toRight}) =>
      toRight ? tipX - arrowDepth : tipX + arrowDepth;

  /// Keeps the distance label inside the visible sky band when the island peak
  /// rises above the viewport during low-altitude final approach.
  static double clampLabelBottomY({
    required double idealBottomY,
    required double horizonY,
    double viewportPaddingTop = 0.0,
  }) {
    final minBottomY =
        viewportPaddingTop + labelTopInset + labelEstimatedHeight;
    final maxBottomY = horizonY - labelPadding;
    final lower = math.min(minBottomY, maxBottomY);
    final upper = math.max(minBottomY, maxBottomY);
    return idealBottomY.clamp(lower, upper);
  }

  /// Computes label anchor and scenery fields for the emergency target island.
  static ({
    IslandViewportMode mode,
    Offset labelPosition,
    Offset labelFractionalTranslation,
    double horizonY,
    double? islandCenterX,
    IslandLandMetrics? land,
    bool? arrowToRight,
    double? arrowTipX,
    double? arrowBaseX,
  }) forTarget({
    required Size size,
    required double relativeBearing,
    required double islandApproach,
    required double altitude,
    required double referenceAltitude,
    double scale = 1.0,
    double viewportPaddingTop = 0.0,
  }) {
    final horizonY = horizonYFor(
      size,
      altitude: altitude,
      referenceAltitude: referenceAltitude,
    );

    if (isOffScreen(relativeBearing)) {
      final toRight = relativeBearing > 0;
      final tipX = arrowTipX(size, toRight: toRight);
      final baseX = arrowBaseX(tipX, toRight: toRight);
      final labelX = toRight
          ? tipX - arrowDepth - arrowLabelGap
          : tipX + arrowDepth + arrowLabelGap;

      return (
        mode: toRight
            ? IslandViewportMode.offScreenRight
            : IslandViewportMode.offScreenLeft,
        labelPosition: Offset(labelX, horizonY),
        labelFractionalTranslation: Offset(toRight ? -1.0 : 0.0, -0.5),
        horizonY: horizonY,
        islandCenterX: null,
        land: null,
        arrowToRight: toRight,
        arrowTipX: tipX,
        arrowBaseX: baseX,
      );
    }

    final centerX = islandCenterX(size, relativeBearing);
    final land = landMetrics(
      size: size,
      progress: islandApproach,
      scale: scale,
      horizonY: horizonY,
    );

    final labelBottomY = clampLabelBottomY(
      idealBottomY: land.peakY - labelPadding,
      horizonY: horizonY,
      viewportPaddingTop: viewportPaddingTop,
    );

    return (
      mode: IslandViewportMode.onIsland,
      labelPosition: Offset(centerX, labelBottomY),
      labelFractionalTranslation: const Offset(-0.5, -1.0),
      horizonY: horizonY,
      islandCenterX: centerX,
      land: land,
      arrowToRight: null,
      arrowTipX: null,
      arrowBaseX: null,
    );
  }
}

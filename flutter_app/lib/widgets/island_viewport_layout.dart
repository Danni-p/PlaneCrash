import 'dart:math' as math;
import 'dart:ui';

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
  static const double horizonFraction = 0.52;
  static const double arrowMargin = 18.0;
  static const double arrowHalfHeight = 26.0;
  static const double arrowDepth = 28.0;
  static const double labelPadding = 12.0;
  static const double arrowLabelGap = 8.0;

  static double horizonYFor(Size size) => size.height * horizonFraction;

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
    double scale = 1.0,
  }) {
    final horizonY = horizonYFor(size);

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

    return (
      mode: IslandViewportMode.onIsland,
      labelPosition: Offset(centerX, land.peakY - labelPadding),
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

/// Operator properties declared in `operator.json`.
///
/// These mirror the properties the Shiny operator
/// (`tercen/pamsoft_grid_shiny_operator`) declared, so that a workflow which
/// swaps the Shiny grid checker for this one keeps the same settings.
///
/// Note which of these the *checker* actually consumes. Shiny's
/// `get_operator_props()` read all of them, but only `Spot Pitch` and
/// `Spot Size` were ever used by the checker UI — to size the drawn spot
/// circles via `off <- (spotPitch * spotSize)/2`. The rest are carried so they
/// round-trip with the workflow and stay available to the gridding operator
/// upstream; they do not affect rendering here.
class OperatorProperties {
  /// Consumed: half of `spotPitch * spotSize` is the drawn spot radius.
  /// A value of 0 means "auto-detect from the image dimensions" — see
  /// [resolveSpotPitch].
  final double spotPitch;

  /// Consumed: fraction of the pitch that a spot occupies.
  final double spotSize;

  // Declared for round-tripping; not used by the checker.
  final double minDiameter;
  final double maxDiameter;
  final double saturationLimit;
  final double edgeSensitivityLow;
  final double edgeSensitivity;
  final String segmentationMethod;
  final String rotation;

  /// Which image to select when a grid is opened.
  ///
  /// * `highest` — the highest-numbered cycle available (the default).
  /// * `grid` — the grid image itself, i.e. the pre-0.0.4 behaviour.
  /// * a number, e.g. `94` — that cycle, falling back to `highest` when the
  ///   cycle is not present for the selected grid.
  final String defaultCycle;

  const OperatorProperties({
    this.spotPitch = 0,
    this.spotSize = 0.66,
    this.minDiameter = 0.45,
    this.maxDiameter = 0.85,
    this.saturationLimit = 4095,
    this.edgeSensitivityLow = 0,
    this.edgeSensitivity = 0.05,
    this.segmentationMethod = 'Edge',
    this.rotation = '-2:0.25:2',
    this.defaultCycle = 'highest',
  });

  /// Property defaults, matching `operator.json`.
  static const OperatorProperties defaults = OperatorProperties();

  /// Resolves a spot pitch in image pixels.
  ///
  /// Shiny left `Spot Pitch` at 0 by default and detected the image set from
  /// the TIFF header (`get_imageset_type`): 552x413 is an Evolve3 and 697x520
  /// an Evolve2. A non-zero property always wins.
  ///
  /// Unknown dimensions fall back to the Evolve3 pitch rather than throwing —
  /// Shiny raised "Cannot automatically detect Spot Pitch", but aborting the
  /// whole viewer over a spot radius is a poor trade in a QC tool.
  static double resolveSpotPitch(
    double spotPitch,
    double imageWidth,
    double imageHeight,
  ) {
    if (spotPitch > 0) return spotPitch;
    if (imageWidth == 697 && imageHeight == 520) return 21.5; // Evolve2
    return 17.0; // Evolve3
  }

  @override
  String toString() => 'OperatorProperties(spotPitch: $spotPitch, '
      'spotSize: $spotSize, minDiameter: $minDiameter, '
      'maxDiameter: $maxDiameter, saturationLimit: $saturationLimit, '
      'edgeSensitivityLow: $edgeSensitivityLow, '
      'edgeSensitivity: $edgeSensitivity, '
      'segmentationMethod: $segmentationMethod, rotation: $rotation, '
      'defaultCycle: $defaultCycle)';
}

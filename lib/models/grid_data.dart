import 'package:pamsoft_grid_flutter_operator/models/fiducial_position.dart';
import 'package:pamsoft_grid_flutter_operator/models/grid_configuration.dart';

/// Contains all grid data for a single grid image.
class GridData {
  /// The grid image this data belongs to.
  final String gridImageId;

  /// Grid configuration parameters (spotPitch, spotSize, center, etc.).
  ///
  /// Mutable because the operator properties and the image's real dimensions
  /// only become known after the grid service has built this object, and the
  /// service hands out a cached instance that callers mutate in place.
  GridConfiguration configuration;

  /// All fiducial positions in the grid.
  final List<FiducialPosition> fiducials;

  /// Global X offset (for whole-grid dragging).
  double globalOffsetX;

  /// Global Y offset (for whole-grid dragging).
  double globalOffsetY;

  /// Grid rotation in radians (for Tercen output).
  double rotation;

  GridData({
    required this.gridImageId,
    required this.configuration,
    required this.fiducials,
    this.globalOffsetX = 0,
    this.globalOffsetY = 0,
    this.rotation = 0,
  });

  /// Creates a deep copy of the grid data.
  GridData copyWith({
    String? gridImageId,
    GridConfiguration? configuration,
    List<FiducialPosition>? fiducials,
    double? globalOffsetX,
    double? globalOffsetY,
    double? rotation,
  }) {
    return GridData(
      gridImageId: gridImageId ?? this.gridImageId,
      configuration: configuration ?? this.configuration.copyWith(),
      fiducials: fiducials ?? this.fiducials.map((f) => f.copyWith()).toList(),
      globalOffsetX: globalOffsetX ?? this.globalOffsetX,
      globalOffsetY: globalOffsetY ?? this.globalOffsetY,
      rotation: rotation ?? this.rotation,
    );
  }

  /// Gets the number of peptide spots.
  int get peptideCount => fiducials.where((f) => !f.isReference).length;

  /// Gets the number of reference fiducials.
  int get referenceCount => fiducials.where((f) => f.isReference).length;

  /// Calculates spot positions from configuration.
  ///
  /// Grid positions are calculated as:
  /// x = centerX + spotPitch * (col - colMidpoint)
  /// y = centerY + spotPitch * (row - rowMidpoint)
  static List<FiducialPosition> calculatePositions(GridConfiguration config) {
    final fiducials = <FiducialPosition>[];
    final rowMidpoint = (config.gridRows - 1) / 2;
    final colMidpoint = (config.gridCols - 1) / 2;

    for (int row = 0; row < config.gridRows; row++) {
      for (int col = 0; col < config.gridCols; col++) {
        final baseX = config.centerX + config.spotPitch * (col - colMidpoint);
        final baseY = config.centerY + config.spotPitch * (row - rowMidpoint);

        fiducials.add(FiducialPosition(
          id: 'peptide_${row}_$col',
          row: row,
          col: col,
          baseX: baseX,
          baseY: baseY,
          diameter: config.spotDiameter,
          isReference: false,
        ));
      }
    }

    return fiducials;
  }

  /// Converts grid data to Tercen output format.
  ///
  /// Returns a list of maps, each representing one fiducial with fields:
  /// - gridX, gridY: Final positions (base + global + individual offsets)
  /// - grdXFixedPosition, grdYFixedPosition: Same as gridX/gridY
  /// - diameter: Spot diameter
  /// - manual: 1 if manually adjusted, 0 otherwise
  /// - bad: 1 if marked bad, 0 otherwise
  /// - empty: 1 if marked empty, 0 otherwise
  /// - grdRotation: Rotation angle in radians
  /// - row, col: Grid coordinates
  List<Map<String, dynamic>> toTercenOutput() {
    return fiducials.map((fiducial) {
      final finalX = fiducial.baseX + globalOffsetX + fiducial.individualOffsetX;
      final finalY = fiducial.baseY + globalOffsetY + fiducial.individualOffsetY;

      return {
        'gridX': finalX,
        'gridY': finalY,
        'grdXFixedPosition': finalX,
        'grdYFixedPosition': finalY,
        'diameter': fiducial.diameter,
        'manual': fiducial.isManual ? 1 : 0,
        'bad': fiducial.isBad ? 1 : 0,
        'empty': fiducial.isEmpty ? 1 : 0,
        'grdRotation': rotation,
        'row': fiducial.row,
        'col': fiducial.col,
        'isReference': fiducial.isReference,
      };
    }).toList();
  }
}

import 'package:flutter/foundation.dart';
import 'package:pamsoft_grid_flutter_operator/di/service_locator.dart';
import 'package:pamsoft_grid_flutter_operator/models/grid_data.dart';
import 'package:pamsoft_grid_flutter_operator/models/enums.dart';
import 'package:pamsoft_grid_flutter_operator/models/grid_configuration.dart';
import 'package:pamsoft_grid_flutter_operator/models/operator_properties.dart';
import 'package:pamsoft_grid_flutter_operator/services/grid_service.dart';
import 'package:pamsoft_grid_flutter_operator/services/image_service.dart';
import 'package:pamsoft_grid_flutter_operator/services/properties_service.dart';
import 'dart:math' as math;

/// Provider for managing grid state and interactions.
class GridProvider extends ChangeNotifier {
  final GridService _gridService = locator<GridService>();
  final PropertiesService _propertiesService = locator<PropertiesService>();

  GridData? _currentGridData;
  String? _currentGridImageId;
  bool _isLoading = false;
  bool _isProcessing = false;
  String? _error;

  OperatorProperties? _properties;

  /// Dimensions of the image currently on screen, once one has been decoded.
  ///
  /// The grid coordinates from Tercen are in image pixels, so the overlay's
  /// scale is only right when the configuration carries the real dimensions —
  /// they used to be hardcoded to the Evolve3 552x413.
  double? _imageWidth;
  double? _imageHeight;

  GridData? get currentGridData => _currentGridData;
  String? get currentGridImageId => _currentGridImageId;
  bool get isLoading => _isLoading;
  bool get isProcessing => _isProcessing;
  String? get error => _error;

  /// Gets the current grid status.
  GridStatus get currentStatus =>
      _currentGridImageId != null
          ? _gridService.getGridStatus(_currentGridImageId!)
          : GridStatus.processed;

  /// Loads grid data for a specific grid image.
  Future<void> loadGrid(String gridImageId) async {
    _isLoading = true;
    _error = null;
    _currentGridImageId = gridImageId;
    notifyListeners();

    try {
      _properties ??= await _propertiesService.getProperties();
      // Mutate in place rather than copyWith: the grid service hands out a
      // cached instance, and edits made through this provider are expected to
      // land on that same object.
      final data = await _gridService.loadGridData(gridImageId);
      data.configuration = _applyProperties(data.configuration);
      _currentGridData = data;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Records the dimensions of the decoded image on screen.
  ///
  /// Called once the image is decoded, which may be after the grid loads, so
  /// the configuration is rebuilt when they arrive or change.
  void setImageSize(double width, double height) {
    if (_imageWidth == width && _imageHeight == height) return;
    _imageWidth = width;
    _imageHeight = height;

    final data = _currentGridData;
    if (data == null) return;
    data.configuration = _applyProperties(data.configuration);
    notifyListeners();
  }

  /// Folds the operator properties and the real image dimensions into a
  /// configuration loaded from the grid service.
  GridConfiguration _applyProperties(GridConfiguration base) {
    final props = _properties ?? OperatorProperties.defaults;
    final width = _imageWidth ?? base.imageWidth;
    final height = _imageHeight ?? base.imageHeight;
    final dimensionsChanged =
        width != base.imageWidth || height != base.imageHeight;

    return base.copyWith(
      spotPitch:
          OperatorProperties.resolveSpotPitch(props.spotPitch, width, height),
      spotSize: props.spotSize,
      imageWidth: width,
      imageHeight: height,
      // Both construction sites centre the grid in the image; keep that true
      // if the dimensions turn out to differ from what the service assumed.
      centerX: dimensionsChanged ? width / 2 : base.centerX,
      centerY: dimensionsChanged ? height / 2 : base.centerY,
    );
  }

  /// Moves the entire grid by an offset.
  void moveWholeGrid(double dx, double dy) {
    if (_currentGridData == null) return;

    _currentGridData!.globalOffsetX += dx;
    _currentGridData!.globalOffsetY += dy;

    // Mark all fiducials as manually adjusted
    for (final fiducial in _currentGridData!.fiducials) {
      fiducial.isManual = true;
    }

    _markAsModified();
    notifyListeners();
  }

  /// Moves a single fiducial by an offset.
  void moveFiducial(String fiducialId, double dx, double dy) {
    if (_currentGridData == null) return;

    final fiducialIndex = _currentGridData!.fiducials.indexWhere(
      (f) => f.id == fiducialId,
    );

    if (fiducialIndex == -1) return;

    _currentGridData!.fiducials[fiducialIndex].individualOffsetX += dx;
    _currentGridData!.fiducials[fiducialIndex].individualOffsetY += dy;
    _currentGridData!.fiducials[fiducialIndex].isManual = true;

    _markAsModified();
    notifyListeners();
  }

  /// Rotates the entire grid around a center point.
  void rotateWholeGrid(double radians, double centerX, double centerY) {
    if (_currentGridData == null) return;

    // Accumulate rotation
    _currentGridData!.rotation += radians;

    final cos = math.cos(radians);
    final sin = math.sin(radians);

    for (final fiducial in _currentGridData!.fiducials) {
      // Get current position
      final currentX = fiducial.x + _currentGridData!.globalOffsetX;
      final currentY = fiducial.y + _currentGridData!.globalOffsetY;

      // Translate to origin (relative to center)
      final relX = currentX - centerX;
      final relY = currentY - centerY;

      // Apply rotation
      final newX = (cos * relX) + (sin * relY);
      final newY = (cos * relY) - (sin * relX);

      // Translate back
      final rotatedX = newX + centerX;
      final rotatedY = newY + centerY;

      // Update fiducial position by adjusting its base coordinates
      // Since we're working with global offset, we need to update the individual offsets
      fiducial.individualOffsetX += rotatedX - currentX;
      fiducial.individualOffsetY += rotatedY - currentY;
      fiducial.isManual = true;
    }

    _markAsModified();
    notifyListeners();
  }

  void _markAsModified() {
    if (_currentGridImageId != null) {
      _gridService.setGridStatus(_currentGridImageId!, GridStatus.modified);
      _gridService.saveGridAdjustments(_currentGridImageId!, _currentGridData!);
    }
  }

  /// Resets to default grid from control file.
  Future<void> resetToDefaultGrid() async {
    if (_currentGridImageId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final defaultGrid = await _gridService.loadDefaultGrid();
      _currentGridData = GridData(
        gridImageId: _currentGridImageId!,
        configuration: defaultGrid.configuration,
        fiducials: defaultGrid.fiducials,
        globalOffsetX: 0,
        globalOffsetY: 0,
      );
      _markAsModified();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves all grid adjustments to Tercen.
  ///
  /// Collects all grid data (modified and unmodified) across all grid images,
  /// builds the output table, and saves via ctx.saveTable().
  Future<void> runProcessing() async {
    _isProcessing = true;
    _error = null;
    notifyListeners();

    try {
      // Save current grid to cache before saving
      if (_currentGridImageId != null && _currentGridData != null) {
        await _gridService.saveGridAdjustments(
            _currentGridImageId!, _currentGridData!);
      }

      // Get all grid image IDs from the image service
      final imageService = locator<ImageService>();
      final gridImages = await imageService.getGridImages();
      final allGridImageIds = gridImages.map((g) => g.id).toList();

      print('📤 Saving all grids to Tercen (${allGridImageIds.length} grid images)');

      // Save all grids to Tercen
      await _gridService.saveAllGrids(allGridImageIds);

      print('✓ All grids saved to Tercen');
    } catch (e) {
      _error = e.toString();
      print('✗ Error saving to Tercen: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
}

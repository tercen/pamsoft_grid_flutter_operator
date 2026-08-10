import 'package:flutter/widgets.dart';
import 'package:pamsoft_grid_flutter_operator/di/service_locator.dart';
import 'package:pamsoft_grid_flutter_operator/models/image_metadata.dart';
import 'package:pamsoft_grid_flutter_operator/models/experiment_data.dart';
import 'package:pamsoft_grid_flutter_operator/models/operator_properties.dart';
import 'package:pamsoft_grid_flutter_operator/services/image_service.dart';
import 'package:pamsoft_grid_flutter_operator/services/properties_service.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tiff_converter.dart';

/// Provider for managing image selection and navigation.
class ImageSelectionProvider extends ChangeNotifier {
  final ImageService _imageService = locator<ImageService>();
  final PropertiesService _propertiesService = locator<PropertiesService>();

  ExperimentData? _experimentData;
  OperatorProperties _properties = OperatorProperties.defaults;
  int _currentGridIndex = 0;
  int _currentImageIndex = 0;
  bool _isLoading = false;
  bool _isLoadingImage = false;
  String? _error;
  DecodedImage? _currentDecodedImage;

  /// Incremented on every selection change so a slow load that has been
  /// superseded discards its result instead of overwriting a newer image.
  int _loadToken = 0;

  ExperimentData? get experimentData => _experimentData;
  OperatorProperties get properties => _properties;
  bool get isLoading => _isLoading;
  bool get isLoadingImage => _isLoadingImage;
  String? get error => _error;
  DecodedImage? get currentDecodedImage => _currentDecodedImage;

  /// Gets the current grid image.
  ImageMetadata? get currentGridImage {
    if (_experimentData == null || _experimentData!.gridImages.isEmpty) {
      return null;
    }
    return _experimentData!.gridImages[_currentGridIndex];
  }

  /// Gets all images for the current grid.
  List<ImageMetadata> get currentGridImages {
    final gridImage = currentGridImage;
    if (gridImage == null || _experimentData == null) return [];
    return _experimentData!.imagesByGrid[gridImage.id] ?? [];
  }

  /// Gets the currently selected image (may be grid or time point).
  ImageMetadata? get currentImage {
    final images = currentGridImages;
    if (images.isEmpty) return null;
    return images[_currentImageIndex.clamp(0, images.length - 1)];
  }

  /// Gets the index of the current grid image.
  int get currentGridIndex => _currentGridIndex;

  /// Gets the index of the current image in the list.
  int get currentImageIndex => _currentImageIndex;

  /// Gets total number of grid images.
  int get gridImageCount => _experimentData?.gridImages.length ?? 0;

  /// Gets the asset path for the current image.
  String get currentImageAssetPath {
    final image = currentImage;
    if (image == null) return '';
    return _imageService.getImageAssetPath(image.id);
  }

  /// Loads experiment data.
  Future<void> loadExperiment() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _properties = await _propertiesService.getProperties();
      _experimentData = await _imageService.loadExperimentData();
      _currentGridIndex = 0;
      _currentImageIndex = _defaultImageIndex();
      _isLoading = false;
      notifyListeners();

      // Load the first image
      await _loadCurrentImage();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Picks the image to select when a grid is opened, honouring the
  /// `Default Cycle` operator property.
  ///
  /// The image list is built grid-image-first, then remaining cycles
  /// descending, so index 0 is always the grid image.
  int _defaultImageIndex() => _defaultImageIndexFor(currentGridImages);

  /// [_defaultImageIndex] for an arbitrary image list, so the choice can also
  /// be computed for a grid that is not the current one (used by prefetch).
  int _defaultImageIndexFor(List<ImageMetadata> images) {
    if (images.isEmpty) return 0;

    final spec = _properties.defaultCycle.trim().toLowerCase();

    // Pre-0.0.4 behaviour, and Shiny's: the grid image itself.
    if (spec == 'grid') return 0;

    // An explicit cycle number, when that cycle exists for this grid.
    if (spec != 'highest') {
      final wanted = int.tryParse(spec);
      if (wanted != null) {
        final index = images.indexWhere((m) => m.cycle == wanted);
        if (index >= 0) return index;
        print('Default Cycle $wanted not present for this grid '
            '— falling back to the highest cycle');
      } else {
        print('Unrecognised Default Cycle "$spec" '
            '— falling back to the highest cycle');
      }
    }

    // 'highest' — and the fallback for anything unresolvable.
    var best = 0;
    for (var i = 1; i < images.length; i++) {
      if (images[i].cycle > images[best].cycle) best = i;
    }
    return best;
  }

  /// Loads and decodes the currently selected image, then warms its
  /// neighbours so stepping through cycles does not wait on the network.
  Future<void> _loadCurrentImage() async {
    final image = currentImage;
    if (image == null) {
      _setDecodedImage(null);
      return;
    }

    final token = ++_loadToken;
    _isLoadingImage = true;
    notifyListeners();

    try {
      final decoded = await _imageService.getDecodedImage(image.id);
      if (token != _loadToken) {
        // Superseded by a newer selection — drop this result.
        decoded?.dispose();
        return;
      }
      _setDecodedImage(decoded);
    } catch (e) {
      print('ImageSelectionProvider: Error loading image: $e');
      if (token == _loadToken) _setDecodedImage(null);
    } finally {
      if (token == _loadToken) {
        _isLoadingImage = false;
        notifyListeners();
      }
    }

    if (token == _loadToken) _prefetchNeighbours();
  }

  /// Warms the cache for the images the user is most likely to ask for next:
  /// the cycles either side of the selection, and the image that opening an
  /// adjacent grid would land on.
  ///
  /// Without the second part, every Grid << / >> hits the network cold, which
  /// is why grid changes felt slower than image changes even after the decode
  /// cost was removed.
  void _prefetchNeighbours() {
    // Deliberately not awaited — these run behind the current image, and the
    // image service collapses duplicate in-flight requests.
    final images = currentGridImages;
    for (final offset in const [1, -1]) {
      final index = _currentImageIndex + offset;
      if (index >= 0 && index < images.length) {
        _imageService.prefetchImage(images[index].id);
      }
    }

    final data = _experimentData;
    if (data == null) return;
    for (final offset in const [1, -1]) {
      final gridIndex = _currentGridIndex + offset;
      if (gridIndex < 0 || gridIndex >= data.gridImages.length) continue;
      final gridImages = data.imagesByGrid[data.gridImages[gridIndex].id];
      if (gridImages == null || gridImages.isEmpty) continue;
      _imageService.prefetchImage(
        gridImages[_defaultImageIndexFor(gridImages)].id,
      );
    }
  }

  void _setDecodedImage(DecodedImage? decoded) {
    if (identical(_currentDecodedImage, decoded)) return;
    final previous = _currentDecodedImage;
    _currentDecodedImage = decoded;

    if (previous != null) {
      // A RawImage in the tree still holds this image until the rebuild that
      // this change triggers has been painted. Disposing it inline can leave a
      // render object drawing a disposed image, so let the frame finish first.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  /// Navigates to the next grid image.
  void nextGrid() {
    if (_experimentData == null) return;
    if (_currentGridIndex < _experimentData!.gridImages.length - 1) {
      _currentGridIndex++;
      _onGridChanged();
    }
  }

  /// Navigates to the previous grid image.
  void previousGrid() {
    if (_currentGridIndex > 0) {
      _currentGridIndex--;
      _onGridChanged();
    }
  }

  /// Sets the current grid by index.
  void setGridIndex(int index) {
    if (_experimentData == null) return;
    if (index >= 0 && index < _experimentData!.gridImages.length) {
      _currentGridIndex = index;
      _onGridChanged();
    }
  }

  void _onGridChanged() {
    _currentImageIndex = _defaultImageIndex();
    _setDecodedImage(null);
    notifyListeners();
    _loadCurrentImage();
  }

  /// Navigates to the next image in the list.
  void nextImage() {
    final images = currentGridImages;
    if (_currentImageIndex < images.length - 1) {
      _currentImageIndex++;
      _onImageIndexChanged();
    }
  }

  /// Navigates to the previous image in the list.
  void previousImage() {
    if (_currentImageIndex > 0) {
      _currentImageIndex--;
      _onImageIndexChanged();
    }
  }

  /// Sets the current image by index.
  void setImageIndex(int index) {
    final images = currentGridImages;
    if (index >= 0 && index < images.length) {
      _currentImageIndex = index;
      _onImageIndexChanged();
    }
  }

  void _onImageIndexChanged() {
    _setDecodedImage(null);
    notifyListeners();
    _loadCurrentImage();
  }

  /// Checks if we can navigate to next grid.
  bool get canGoNextGrid =>
      _experimentData != null &&
      _currentGridIndex < _experimentData!.gridImages.length - 1;

  /// Checks if we can navigate to previous grid.
  bool get canGoPreviousGrid => _currentGridIndex > 0;

  /// Checks if we can navigate to next image.
  bool get canGoNextImage => _currentImageIndex < currentGridImages.length - 1;

  /// Checks if we can navigate to previous image.
  bool get canGoPreviousImage => _currentImageIndex > 0;

  @override
  void dispose() {
    _currentDecodedImage?.dispose();
    _currentDecodedImage = null;
    super.dispose();
  }
}

import 'package:pamsoft_grid_flutter_operator/models/image_metadata.dart';
import 'package:pamsoft_grid_flutter_operator/models/experiment_data.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tiff_converter.dart';

/// Abstract interface for image service.
///
/// Provides methods to load, query, and manage experiment images.
abstract class ImageService {
  /// Loads all experiment data including grid images and their time points.
  ///
  /// Returns a [Future] that completes with [ExperimentData].
  Future<ExperimentData> loadExperimentData();

  /// Gets all grid images (T100 time points).
  ///
  /// Returns a list of [ImageMetadata] representing grid images.
  Future<List<ImageMetadata>> getGridImages();

  /// Gets all images for a specific grid image group.
  ///
  /// [gridImageId] - The ID of the grid image.
  /// Returns all time points associated with that Well/Field combination.
  Future<List<ImageMetadata>> getImagesForGrid(String gridImageId);

  /// Gets the asset path for displaying an image.
  ///
  /// In mock implementation, cycles through available sample images.
  /// [imageId] - The image identifier.
  String getImageAssetPath(String imageId);

  /// Fetches a TIFF image and decodes it for display.
  ///
  /// [imageId] - The image identifier.
  /// Returns a [DecodedImage] or null if the fetch or decode fails.
  ///
  /// The caller owns the returned image and must [DecodedImage.dispose] it
  /// once it is no longer displayed.
  Future<DecodedImage?> getDecodedImage(String imageId);

  /// Warms the cache for [imageId] so a later [getDecodedImage] is fast.
  ///
  /// Fetching dominates the cost of showing an image, so pulling neighbours
  /// in the background is what makes stepping through cycles feel instant.
  /// Errors are swallowed: a failed prefetch must never surface to the user,
  /// it just means the real fetch happens later.
  Future<void> prefetchImage(String imageId);

  /// Parses filename to extract metadata.
  ///
  /// Returns parsed components: experimentId, well, field, time, position, etc.
  ImageMetadata parseFilename(String filename);
}

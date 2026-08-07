import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:pamsoft_grid_flutter_operator/models/image_metadata.dart';
import 'package:pamsoft_grid_flutter_operator/models/image_metadata_impl.dart';
import 'package:pamsoft_grid_flutter_operator/models/experiment_data.dart';
import 'package:pamsoft_grid_flutter_operator/services/image_service.dart';
import 'package:pamsoft_grid_flutter_operator/utils/asset_helper.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tiff_converter.dart';

/// Mock implementation of ImageService for development and testing.
///
/// Uses real TIFF files from the TIFF folder and converts them to PNG at runtime.
class MockImageService implements ImageService {
  // Available TIFF files (maps imageId to filename)
  static const List<String> _availableTiffs = [
    '641070511_W1_F1_T100_P94_I473_A29.tif',
    '641070514_W2_F1_T100_P94_I498_A30.tif',
    '641070516_W3_F1_T100_P94_I523_A29.tif',
    '641070612_W4_F1_T100_P94_I488_A29.tif',
  ];

  // Cache for fetched TIFF bytes
  final Map<String, Uint8List> _imageCache = {};

  // Mock grid images (representing different Well/Field combinations)
  final List<ImageMetadata> _gridImages = [];
  final Map<String, List<ImageMetadata>> _imagesByGrid = {};

  MockImageService() {
    _initializeMockData();
  }

  void _initializeMockData() {
    // Parse actual TIFF filenames to create grid images
    for (final tiffFilename in _availableTiffs) {
      final metadata = parseFilename(tiffFilename);
      _gridImages.add(metadata.copyWith(isGridImage: true));

      // For each grid image, create a list with just that image
      // (in production, this would have multiple time points)
      _imagesByGrid[metadata.id] = [metadata.copyWith(isGridImage: true)];
    }
  }

  @override
  Future<ExperimentData> loadExperimentData() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return ExperimentData(
      experimentId: 'multi',
      gridImages: _gridImages,
      imagesByGrid: _imagesByGrid,
    );
  }

  @override
  Future<List<ImageMetadata>> getGridImages() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return List.from(_gridImages);
  }

  @override
  Future<List<ImageMetadata>> getImagesForGrid(String gridImageId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _imagesByGrid[gridImageId] ?? [];
  }

  @override
  String getImageAssetPath(String imageId) {
    // Return path to TIFF file (used for fallback if bytes not loaded)
    return 'assets/images/TIFF/$imageId.tif';
  }

  @override
  Future<DecodedImage?> getDecodedImage(String imageId) async {
    final tiffBytes = await _getTiffBytes(imageId);
    if (tiffBytes == null) return null;
    return TiffConverter.tiffToImage(tiffBytes);
  }

  @override
  Future<void> prefetchImage(String imageId) async {
    if (_imageCache.containsKey(imageId)) return;
    try {
      await _getTiffBytes(imageId);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<Uint8List?> _getTiffBytes(String imageId) async {
    final cached = _imageCache[imageId];
    if (cached != null) return cached;

    try {
      // Construct URL for TIFF file
      final tiffUrl = AssetHelper.getAssetUrl('assets/images/TIFF/$imageId.tif');
      print('MockImageService: Fetching TIFF from $tiffUrl');

      // Fetch TIFF bytes via HTTP
      final tiffBytes = await _fetchBytes(tiffUrl);
      if (tiffBytes == null) {
        print('MockImageService: Failed to fetch TIFF bytes');
        return null;
      }

      print('MockImageService: Fetched ${tiffBytes.length} bytes');
      _imageCache[imageId] = tiffBytes;
      return tiffBytes;
    } catch (e) {
      print('MockImageService._getTiffBytes error: $e');
      return null;
    }
  }

  /// Fetches binary data from a URL using XMLHttpRequest.
  Future<Uint8List?> _fetchBytes(String url) async {
    try {
      final request = web.XMLHttpRequest();
      request.open('GET', url, true);
      request.responseType = 'arraybuffer';

      final completer = Completer<Uint8List?>();

      request.onload = ((web.Event event) {
        if (request.status == 200) {
          final response = request.response;
          if (response != null) {
            final arrayBuffer = response as JSArrayBuffer;
            final bytes = arrayBuffer.toDart.asUint8List();
            completer.complete(bytes);
          } else {
            completer.complete(null);
          }
        } else {
          print('MockImageService: HTTP error ${request.status}');
          completer.complete(null);
        }
      }).toJS;

      request.onerror = ((web.Event event) {
        print('MockImageService: Network error');
        completer.complete(null);
      }).toJS;

      request.send();
      return await completer.future;
    } catch (e) {
      print('MockImageService._fetchBytes error: $e');
      return null;
    }
  }

  @override
  ImageMetadata parseFilename(String filename) {
    // Parse: {ExperimentID}_{Well}_{Field}_{Time}_{Position}_{Image}_{Array}.tif
    final cleanName = filename.replaceAll('.tif', '').replaceAll('.png', '');
    final parts = cleanName.split('_');
    return ImageMetadataImpl(
      id: cleanName,
      filename: filename,
      experimentId: parts.isNotEmpty ? parts[0] : '',
      well: parts.length > 1 ? parts[1] : '',
      field: parts.length > 2 ? parts[2] : '',
      timePoint: parts.length > 3 ? parts[3] : '',
      position: parts.length > 4 ? parts[4] : '',
      imageNumber: parts.length > 5 ? parts[5] : '',
      array: parts.length > 6 ? parts[6] : '',
      isGridImage: parts.length > 3 && parts[3] == 'T100',
    );
  }
}

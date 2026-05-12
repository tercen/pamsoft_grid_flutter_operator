import 'dart:typed_data';
import 'package:pamsoft_grid_flutter_operator/models/image_metadata.dart';
import 'package:pamsoft_grid_flutter_operator/models/experiment_data.dart';
import 'package:pamsoft_grid_flutter_operator/services/image_service.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tercen_url_parser.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tiff_converter.dart';
import 'package:pamsoft_grid_flutter_operator/utils/document_id_resolver.dart';
import 'package:sci_tercen_client/sci_client_service_factory.dart';
import 'package:sci_tercen_context/src/context/operator_context.dart';

/// Tercen implementation of ImageService.
///
/// Loads image metadata from a Tercen ZIP via FileService.listZipContents
/// (no full-ZIP download) and fetches individual TIFFs on demand via
/// FileService.downloadZipEntry. Grid image grouping comes from Tercen
/// column data (grdImageNameUsed/Image columns).
class TercenImageService implements ImageService {
  final ServiceFactory _factory;
  final TercenUrlParser _urlParser;
  final ImageService _mockService;

  // Cache for loaded data
  ExperimentData? _cachedData;
  final Map<String, Uint8List> _imageCache = {};

  // The Tercen FileDocument id for the ZIP and a map from image id (parsed
  // from filename) to ZIP entry path. The ZIP itself is never downloaded;
  // listZipContents gives us names + sizes, and individual TIFFs are
  // fetched on demand through downloadZipEntry.
  String? _loadedDocumentId;
  final Map<String, String> _entryPathByImageId = {};

  TercenImageService(this._factory, this._urlParser, this._mockService);

  @override
  Future<ExperimentData> loadExperimentData() async {
    if (_cachedData != null) {
      return _cachedData!;
    }

    try {
      print('Loading experiment data from Tercen (lazy loading mode)');

      // Use DocumentIdResolver to get the actual .documentId
      final resolver = DocumentIdResolver(_urlParser);
      final resolvedIds = await resolver.resolveDocumentId();

      if (resolvedIds == null || resolvedIds.documentId == null) {
        throw Exception('Failed to resolve .documentId - DocumentIdResolver returned null');
      }

      final documentId = resolvedIds.documentId!;
      print('Resolved .documentId: $documentId');

      // List ZIP entries (cheap metadata fetch — no full-ZIP download).
      // Individual TIFFs are fetched on demand in getImageBytes().
      final images = await _listZipEntriesAndExtractMetadata(documentId);
      print('Found ${images.length} images in ZIP (will fetch on demand)');

      // Fetch Tercen column data for grid image grouping
      final tercenGrouping = await _fetchTercenGrouping();

      // Build experiment data using Tercen grouping (matching Shiny behavior)
      final experimentData = _buildExperimentData(images, tercenGrouping);

      _cachedData = experimentData;
      return experimentData;
    } catch (e, stackTrace) {
      print('ERROR loading experiment data from Tercen: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Fetches grdImageNameUsed and Image columns from Tercen cselect.
  ///
  /// Returns a map of gridImageName -> list of associated image names,
  /// matching Shiny's get_image_used_list() and get_image_list() logic.
  Future<Map<String, List<String>>> _fetchTercenGrouping() async {
    if (_urlParser.taskId == null) {
      print('No taskId - falling back to ZIP-only grouping');
      return {};
    }

    try {
      final ctx = await OperatorContext.create(
        serviceFactory: _factory,
        taskId: _urlParser.taskId!,
      );

      // Find column names with namespace prefix
      final colNames = await ctx.cnames;
      final grdImageCol = colNames.firstWhere(
        (n) => n.endsWith('grdImageNameUsed'),
        orElse: () => '',
      );
      final imageCol = colNames.firstWhere(
        (n) => n.endsWith('Image'),
        orElse: () => '',
      );

      if (grdImageCol.isEmpty || imageCol.isEmpty) {
        print('Missing required columns: grdImageNameUsed=$grdImageCol, Image=$imageCol');
        return {};
      }

      print('Fetching Tercen column data: $grdImageCol, $imageCol');
      final colData = await ctx.cselect(names: [grdImageCol, imageCol]);

      List grdImageValues = [];
      List imageValues = [];
      for (final col in colData.columns) {
        if (col.name == grdImageCol) grdImageValues = col.values as List;
        if (col.name == imageCol) imageValues = col.values as List;
      }

      // Build grouping: grdImageNameUsed -> unique Image values
      final grouping = <String, List<String>>{};
      for (int i = 0; i < grdImageValues.length; i++) {
        final gridName = grdImageValues[i].toString();
        final imageName = imageValues[i].toString();
        grouping.putIfAbsent(gridName, () => []);
        if (!grouping[gridName]!.contains(imageName)) {
          grouping[gridName]!.add(imageName);
        }
      }

      print('Tercen grouping: ${grouping.length} grid images');
      for (final entry in grouping.entries) {
        print('  ${entry.key} -> ${entry.value.length} images');
      }

      return grouping;
    } catch (e) {
      print('Error fetching Tercen grouping: $e');
      return {};
    }
  }

  /// Lists ZIP entries via FileService.listZipContents and builds image
  /// metadata. The ZIP itself is never downloaded — only entry names are
  /// fetched. The mapping imageId → entry path is kept so getImageBytes
  /// can stream individual TIFFs through FileService.downloadZipEntry.
  Future<List<ImageMetadata>> _listZipEntriesAndExtractMetadata(
      String documentId) async {
    try {
      final fileService = _factory.fileService;

      print('📥 Listing ZIP entries for .documentId: $documentId');
      final entries = await fileService.listZipContents(documentId);

      _loadedDocumentId = documentId;
      _entryPathByImageId.clear();

      print('📂 ZIP archive contains ${entries.length} entries');

      final images = <ImageMetadata>[];
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        if (entry.name.contains('ImageResults/') &&
            entry.name.endsWith('.tif')) {
          // Extract filename from path and parse it into ImageMetadata
          final filename = entry.name.split('/').last;
          final metadata = parseFilename(filename);
          images.add(metadata);
          _entryPathByImageId[metadata.id] = entry.name;

          print('  Found: $filename');
        }
      }

      print('✓ Extracted metadata for ${images.length} images');

      return images;
    } catch (e) {
      print('✗ Error listing ZIP entries for $documentId: $e');
      rethrow;
    }
  }

  /// Extracts peptide number from image name (5th underscore part).
  /// e.g., "641031403_W1_F1_T100_P94_I473_A29" → 94
  static int _extractPeptideNumber(String imageName) {
    final parts = imageName.split('_');
    if (parts.length > 4) {
      final peptide = parts[4]; // e.g., "P94"
      return int.tryParse(peptide.substring(1)) ?? 0;
    }
    return 0;
  }

  ExperimentData _buildExperimentData(
    List<ImageMetadata> zipImages,
    Map<String, List<String>> tercenGrouping,
  ) {
    // Build lookup map: image id -> ImageMetadata from ZIP
    final metadataById = <String, ImageMetadata>{};
    for (final img in zipImages) {
      metadataById[img.id] = img;
    }

    final gridImages = <ImageMetadata>[];
    final imagesByGrid = <String, List<ImageMetadata>>{};

    if (tercenGrouping.isNotEmpty) {
      // Use Tercen data for grouping (matching Shiny behavior).
      // Grid images = unique grdImageNameUsed values from Tercen cselect.
      // Image list per grid = Image values where grdImageNameUsed == selected,
      //   sorted: grid image first, then others by peptide number descending.
      for (final gridName in tercenGrouping.keys) {
        final metadata = metadataById[gridName];
        if (metadata == null) {
          print('Grid image $gridName not found in ZIP, skipping');
          continue;
        }

        gridImages.add(metadata.copyWith(isGridImage: true));

        // Get associated images, matching Shiny's get_image_list():
        // 1. Remove grid image from list
        // 2. Sort remaining by peptide number descending
        // 3. Prepend grid image at front
        final associatedNames = tercenGrouping[gridName]!;
        final others = associatedNames.where((n) => n != gridName).toList();

        // Sort by peptide number descending (Shiny: decreasing = TRUE)
        others.sort((a, b) {
          final aNum = _extractPeptideNumber(a);
          final bNum = _extractPeptideNumber(b);
          return bNum.compareTo(aNum);
        });

        // Build metadata list: grid image first, then sorted others
        final sortedMetadata = <ImageMetadata>[];
        sortedMetadata.add(metadata.copyWith(isGridImage: true));
        for (final name in others) {
          final meta = metadataById[name];
          if (meta != null) {
            sortedMetadata.add(meta);
          }
        }

        imagesByGrid[gridName] = sortedMetadata;
      }
    } else {
      // Fallback: ZIP-only grouping (P94 T100 images as grid images)
      for (final image in zipImages) {
        if (image.isGridImage && image.position == 'P94') {
          gridImages.add(image);
          imagesByGrid[image.id] = [image];
        }
      }
    }

    print('Built experiment data: ${gridImages.length} grid images');
    for (final gi in gridImages) {
      final count = imagesByGrid[gi.id]?.length ?? 0;
      print('  Grid: ${gi.id} -> $count associated images');
    }

    final experimentId = zipImages.isNotEmpty ? zipImages.first.experimentId : 'tercen';

    return ExperimentData(
      experimentId: experimentId,
      gridImages: gridImages,
      imagesByGrid: imagesByGrid,
    );
  }

  @override
  Future<List<ImageMetadata>> getGridImages() async {
    final data = await loadExperimentData();
    return data.gridImages;
  }

  @override
  Future<List<ImageMetadata>> getImagesForGrid(String gridImageId) async {
    final data = await loadExperimentData();
    return data.imagesByGrid[gridImageId] ?? [];
  }

  @override
  String getImageAssetPath(String imageId) {
    // Not used for Tercen - images are loaded from cache
    return '';
  }

  @override
  Future<Uint8List?> getImageBytes(String imageId) async {
    // Return cached PNG bytes if available
    if (_imageCache.containsKey(imageId)) {
      print('  ✓ Returning cached image: $imageId');
      return _imageCache[imageId];
    }

    // Ensure metadata is loaded
    if (_loadedDocumentId == null) {
      print('  Loading experiment data first...');
      await loadExperimentData();
    }
    if (_loadedDocumentId == null) {
      print('  ✗ No documentId available');
      return null;
    }

    final entryPath = _entryPathByImageId[imageId];
    if (entryPath == null) {
      print('  ✗ No ZIP entry mapping for imageId: $imageId');
      return null;
    }

    try {
      print('  📥 Fetching ZIP entry: $entryPath');
      final fileService = _factory.fileService;

      // Stream the single TIFF entry from the server
      final chunks = <List<int>>[];
      await for (final chunk
          in fileService.downloadZipEntry(_loadedDocumentId!, entryPath)) {
        chunks.add(chunk);
      }

      final totalLength = chunks.fold<int>(0, (s, c) => s + c.length);
      final tiffData = Uint8List(totalLength);
      var offset = 0;
      for (final chunk in chunks) {
        tiffData.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      print('    Converting TIFF (${tiffData.length} bytes)');
      final pngBytes = TiffConverter.tiffToPng(tiffData);

      if (pngBytes != null) {
        _imageCache[imageId] = pngBytes;
        print('    ✓ Converted to PNG (${pngBytes.length} bytes)');
        return pngBytes;
      } else {
        print('    ✗ Failed to convert TIFF to PNG');
        return null;
      }
    } catch (e) {
      print('  ✗ Error fetching/converting ZIP entry $entryPath: $e');
      return null;
    }
  }

  @override
  ImageMetadata parseFilename(String filename) {
    // Use mock service's filename parser
    return _mockService.parseFilename(filename);
  }
}

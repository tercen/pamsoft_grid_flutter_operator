import 'dart:typed_data';
import 'package:pamsoft_grid_flutter_operator/models/image_metadata.dart';

/// Concrete implementation of ImageMetadata.
class ImageMetadataImpl implements ImageMetadata {
  @override
  final String id;

  @override
  final String filename;

  @override
  final String experimentId;

  @override
  final String well;

  @override
  final String field;

  @override
  final String timePoint;

  @override
  final String position;

  @override
  final String imageNumber;

  @override
  final String array;

  @override
  final bool isGridImage;

  @override
  final Uint8List? imageBytes;

  const ImageMetadataImpl({
    required this.id,
    required this.filename,
    required this.experimentId,
    required this.well,
    required this.field,
    required this.timePoint,
    required this.position,
    required this.imageNumber,
    required this.array,
    this.isGridImage = false,
    this.imageBytes,
  });

  @override
  String get displayName => id;

  @override
  int get cycle {
    if (position.length < 2) return 0;
    return int.tryParse(position.substring(1)) ?? 0;
  }

  @override
  ImageMetadata copyWith({bool? isGridImage, Uint8List? imageBytes}) {
    return ImageMetadataImpl(
      id: id,
      filename: filename,
      experimentId: experimentId,
      well: well,
      field: field,
      timePoint: timePoint,
      position: position,
      imageNumber: imageNumber,
      array: array,
      isGridImage: isGridImage ?? this.isGridImage,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageMetadata &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

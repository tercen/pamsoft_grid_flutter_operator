import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A decoded image, ready to hand to `RawImage`, plus its pixel dimensions.
class DecodedImage {
  final ui.Image image;
  final int width;
  final int height;

  const DecodedImage(this.image, this.width, this.height);

  void dispose() => image.dispose();
}

/// Utility class for decoding 16-bit grayscale TIFF images for display.
///
/// This is specifically designed for Pamgene/Pamstation TIFF images which are
/// typically 12-bit grayscale data stored in 16-bit format, uncompressed.
///
/// This decodes straight from TIFF bytes to an RGBA buffer and then to a
/// [ui.Image]. It deliberately does *not* go via PNG. The previous pipeline
/// encoded the decoded pixels to PNG only so that `Image.memory` — which
/// accepts encoded bytes only — could decode them straight back. Measured on a
/// dart2js release build against a 552x413 sample, that round trip cost
/// 146 ms per image, of which `encodePng` alone was 129 ms (88%). Going
/// direct is ~8 ms. The encode also ran synchronously on the main thread, so
/// it froze the frame loop — the loading spinner could not even animate.
class TiffConverter {
  /// Decodes 16-bit grayscale TIFF bytes into a display-ready [ui.Image].
  ///
  /// Returns null if the bytes are not a TIFF this decoder understands.
  static Future<DecodedImage?> tiffToImage(Uint8List tiffBytes) async {
    final pixels = decodeToRgba(tiffBytes);
    if (pixels == null) return null;

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels.rgba,
      pixels.width,
      pixels.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return DecodedImage(await completer.future, pixels.width, pixels.height);
  }

  /// Reads just the dimensions from a TIFF header, without decoding pixels.
  static ({int width, int height})? readDimensions(Uint8List bytes) {
    final header = _parseHeader(bytes);
    if (header == null) return null;
    return (width: header.width, height: header.height);
  }

  /// Decodes an uncompressed 16-bit grayscale TIFF into an RGBA byte buffer.
  ///
  /// The 12-bit sample values are shifted down to 8 bits and written to all
  /// three colour channels, since `ui.PixelFormat` has no grayscale variant.
  static TiffPixels? decodeToRgba(Uint8List bytes) {
    try {
      final header = _parseHeader(bytes);
      if (header == null) return null;

      final data = ByteData.sublistView(bytes);
      final width = header.width;
      final height = header.height;
      final byteOrder = header.byteOrder;

      final rgba = Uint8List(width * height * 4);
      var out = 0;
      var y = 0;

      for (var stripIndex = 0;
          stripIndex < header.stripOffsets.length && y < height;
          stripIndex++) {
        var pixelOffset = header.stripOffsets[stripIndex];
        final rowsInStrip = (y + header.rowsPerStrip > height)
            ? height - y
            : header.rowsPerStrip;

        for (var row = 0; row < rowsInStrip && y < height; row++, y++) {
          for (var x = 0; x < width; x++) {
            if (pixelOffset + 1 >= bytes.length) break;

            // Read the 16-bit sample; 12-bit data sits in the low bits, so
            // shifting right by 4 maps 0-4095 onto 0-255.
            final value = (data.getUint16(pixelOffset, byteOrder) >> 4) & 0xFF;

            rgba[out++] = value;
            rgba[out++] = value;
            rgba[out++] = value;
            rgba[out++] = 255;
            pixelOffset += 2;
          }
        }
      }

      return TiffPixels(rgba, width, height);
    } catch (e) {
      print('TiffConverter.decodeToRgba error: $e');
      return null;
    }
  }

  /// Parses the TIFF header and first IFD.
  static _TiffHeader? _parseHeader(Uint8List bytes) {
    try {
      if (bytes.length < 8) {
        print('TiffConverter: File too small');
        return null;
      }

      final byteOrder = bytes[0] == 0x49 ? Endian.little : Endian.big;
      final data = ByteData.sublistView(bytes);

      // Verify TIFF magic number (42)
      final magic = data.getUint16(2, byteOrder);
      if (magic != 42) {
        print('TiffConverter: Not a valid TIFF file (magic=$magic)');
        return null;
      }

      final ifdOffset = data.getUint32(4, byteOrder);
      final numEntries = data.getUint16(ifdOffset, byteOrder);

      int? width, height, rowsPerStrip;
      int stripOffsetsValue = 0;
      int stripOffsetsCount = 0;
      int stripOffsetsType = 0;

      for (var i = 0; i < numEntries; i++) {
        final entryOffset = ifdOffset + 2 + (i * 12);
        final tag = data.getUint16(entryOffset, byteOrder);
        final type = data.getUint16(entryOffset + 2, byteOrder);
        final count = data.getUint32(entryOffset + 4, byteOrder);

        // SHORT (type 3) is 2 bytes; LONG and offsets are 4.
        final value = type == 3
            ? data.getUint16(entryOffset + 8, byteOrder)
            : data.getUint32(entryOffset + 8, byteOrder);

        switch (tag) {
          case 256: // ImageWidth
            width = value;
          case 257: // ImageLength (height)
            height = value;
          case 273: // StripOffsets
            stripOffsetsValue = value;
            stripOffsetsCount = count;
            stripOffsetsType = type;
          case 278: // RowsPerStrip
            rowsPerStrip = value;
        }
      }

      if (width == null || height == null) {
        print('TiffConverter: Missing required TIFF tags (width/height)');
        return null;
      }

      rowsPerStrip ??= height;

      final stripOffsets = <int>[];
      if (stripOffsetsCount == 1) {
        stripOffsets.add(stripOffsetsValue);
      } else {
        // The tag value is an offset to an array of strip offsets.
        for (var i = 0; i < stripOffsetsCount; i++) {
          stripOffsets.add(stripOffsetsType == 3
              ? data.getUint16(stripOffsetsValue + i * 2, byteOrder)
              : data.getUint32(stripOffsetsValue + i * 4, byteOrder));
        }
      }

      return _TiffHeader(
        width: width,
        height: height,
        rowsPerStrip: rowsPerStrip,
        stripOffsets: stripOffsets,
        byteOrder: byteOrder,
      );
    } catch (e) {
      print('TiffConverter._parseHeader error: $e');
      return null;
    }
  }
}

/// A decoded RGBA pixel buffer and its dimensions.
class TiffPixels {
  final Uint8List rgba;
  final int width;
  final int height;

  const TiffPixels(this.rgba, this.width, this.height);
}

class _TiffHeader {
  final int width;
  final int height;
  final int rowsPerStrip;
  final List<int> stripOffsets;
  final Endian byteOrder;

  const _TiffHeader({
    required this.width,
    required this.height,
    required this.rowsPerStrip,
    required this.stripOffsets,
    required this.byteOrder,
  });
}

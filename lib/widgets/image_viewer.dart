import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pamsoft_grid_flutter_operator/providers/settings_provider.dart';
import 'package:pamsoft_grid_flutter_operator/providers/image_selection_provider.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/grid_canvas.dart';
import 'package:pamsoft_grid_flutter_operator/utils/image_filters.dart';
import 'package:pamsoft_grid_flutter_operator/utils/constants.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tiff_converter.dart';

/// Widget for displaying the TIFF/PNG image with grid overlay.
class ImageViewer extends StatelessWidget {
  const ImageViewer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ImageSelectionProvider, SettingsProvider>(
      builder: (context, imageProvider, settingsProvider, child) {
        final decoded = imageProvider.currentDecodedImage;
        final isLoadingImage = imageProvider.isLoadingImage;
        final currentImage = imageProvider.currentImage;

        if (currentImage == null) {
          return const Center(
            child: Text('No image selected'),
          );
        }

        // Size from the decoded image's own dimensions so image sets other
        // than Evolve3 (552x413) are not squashed into its aspect ratio.
        // Falls back to the Evolve3 constants until the first decode lands.
        final width = (decoded?.width ?? AppConstants.imageOriginalWidth) *
            AppConstants.imageDisplayScale;
        final height = (decoded?.height ?? AppConstants.imageOriginalHeight) *
            AppConstants.imageDisplayScale;

        return Center(
          child: Container(
            width: width.toDouble(),
            height: height.toDouble(),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.grey.shade700, width: 1),
            ),
            child: ClipRect(
              child: Stack(
                children: [
                  // Image with brightness/contrast filter - fills container
                  Positioned.fill(
                    child: ColorFiltered(
                      colorFilter: ImageFilters.createBrightnessContrastFilter(
                        brightness: settingsProvider.brightness,
                        contrast: settingsProvider.contrast,
                      ),
                      child: _buildImage(decoded, isLoadingImage),
                    ),
                  ),
                  // Grid overlay - clipped to container bounds.
                  // LayoutBuilder captures the actual inner dimensions (excluding
                  // the Container's 1px border) so the grid scale matches the image.
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) => GridCanvas(
                        containerWidth: constraints.maxWidth,
                        containerHeight: constraints.maxHeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImage(DecodedImage? decoded, bool isLoading) {
    if (isLoading) {
      // "Loading image", not "Converting TIFF": this spinner covers the fetch
      // as well as the decode, and the fetch is now the slower of the two.
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading image...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (decoded != null) {
      return RawImage(
        image: decoded.image,
        fit: BoxFit.fill,
      );
    }

    return _buildErrorWidget();
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            'Failed to load image',
            style: TextStyle(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

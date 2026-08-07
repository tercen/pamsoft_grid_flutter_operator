import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pamsoft_grid_flutter_operator/core/theme/app_spacing.dart';
import 'package:pamsoft_grid_flutter_operator/core/version/version_info.dart';
import 'package:pamsoft_grid_flutter_operator/providers/grid_provider.dart';
import 'package:pamsoft_grid_flutter_operator/providers/image_selection_provider.dart';
import 'package:pamsoft_grid_flutter_operator/utils/constants.dart';
import 'package:pamsoft_grid_flutter_operator/presentation/widgets/app_shell.dart';
import 'package:pamsoft_grid_flutter_operator/presentation/widgets/left_panel/left_panel.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/grid_dropdown.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/navigation_buttons.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/image_list.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/pagination_controls.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/image_viewer.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/status_indicator.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/brightness_contrast_sliders.dart';
import 'package:pamsoft_grid_flutter_operator/widgets/action_buttons.dart';

/// Main home screen of the application.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FocusNode _focusNode = FocusNode();

  /// Stored reference to remove the listener on dispose.
  ImageSelectionProvider? _imageProvider;

  /// Tracks the last image ID for which a grid was loaded.
  String? _lastLoadedImageId;

  @override
  void initState() {
    super.initState();
    // Load experiment data when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _imageProvider = context.read<ImageSelectionProvider>();
        _imageProvider!.addListener(_onImageChanged);
        _loadData();
      }
    });
  }

  Future<void> _loadData() async {
    final imageProvider = context.read<ImageSelectionProvider>();
    final gridProvider = context.read<GridProvider>();

    await imageProvider.loadExperiment();

    // Load grid for the first selected image
    final firstImageId = imageProvider.currentImage?.id;
    if (firstImageId != null) {
      _lastLoadedImageId = firstImageId;
      await gridProvider.loadGrid(firstImageId);
    }
  }

  /// Called whenever ImageSelectionProvider notifies listeners.
  /// Reloads the grid whenever the selected image changes, regardless of
  /// how the navigation occurred (list tap, nav buttons, dropdown, keyboard).
  void _onImageChanged() {
    if (!mounted) return;
    final imageProvider = context.read<ImageSelectionProvider>();
    final gridProvider = context.read<GridProvider>();
    final currentImageId = imageProvider.currentImage?.id;
    if (currentImageId != null && currentImageId != _lastLoadedImageId) {
      _lastLoadedImageId = currentImageId;
      gridProvider.loadGrid(currentImageId);
    }

    // Feed the decoded image's real dimensions to the grid, which otherwise
    // assumes the Evolve3 552x413 and would mis-scale any other image set.
    final decoded = imageProvider.currentDecodedImage;
    if (decoded != null) {
      gridProvider.setImageSize(
        decoded.width.toDouble(),
        decoded.height.toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _imageProvider?.removeListener(_onImageChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final imageProvider = context.read<ImageSelectionProvider>();

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (imageProvider.canGoPreviousGrid) {
          imageProvider.previousGrid();
          // _onImageChanged listener will handle the grid reload
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (imageProvider.canGoNextGrid) {
          imageProvider.nextGrid();
          // _onImageChanged listener will handle the grid reload
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Consumer<ImageSelectionProvider>(
        builder: (context, imageProvider, child) {
          if (imageProvider.isLoading) {
            return Scaffold(
              backgroundColor: colorScheme.surfaceContainerHighest,
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (imageProvider.error != null) {
            return Scaffold(
              backgroundColor: colorScheme.surfaceContainerHighest,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Error: ${imageProvider.error}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(
                      onPressed: _loadData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          return AppShell(
            appTitle: AppConstants.appTitle,
            appIcon: FontAwesomeIcons.grip,
            sections: _buildSections(context),
            content: _buildMainContent(context),
          );
        },
      ),
    );
  }

  List<LeftPanelSection> _buildSections(BuildContext context) {
    return [
      // NAVIGATION section
      LeftPanelSection(
        icon: FontAwesomeIcons.compass,
        label: 'Navigation',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GridDropdown(),
            const SizedBox(height: AppSpacing.sm),
            GridNavigationButtons(),
            const SizedBox(height: AppSpacing.xs),
            const ImageNavigationButtons(),
          ],
        ),
      ),

      // IMAGES section
      LeftPanelSection(
        icon: FontAwesomeIcons.images,
        label: 'Images',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PaginationControls(),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: 220,
              child: Card(
                margin: EdgeInsets.zero,
                child: const ImageList(),
              ),
            ),
          ],
        ),
      ),

      // DISPLAY section
      LeftPanelSection(
        icon: FontAwesomeIcons.sliders,
        label: 'Display',
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrightnessSlider(),
            SizedBox(height: AppSpacing.xs),
            ContrastSlider(),
          ],
        ),
      ),

      // ACTIONS section
      LeftPanelSection(
        icon: FontAwesomeIcons.bolt,
        label: 'Actions',
        content: const ActionButtons(),
      ),

      // INFO section (required)
      LeftPanelSection(
        icon: FontAwesomeIcons.circleInfo,
        label: 'Info',
        content: _buildInfoContent(context),
      ),
    ];
  }

  Widget _buildMainContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer2<ImageSelectionProvider, GridProvider>(
      builder: (context, imageProvider, gridProvider, child) {
        // The header names the image actually on screen, not the grid image
        // it belongs to — those diverge as soon as you step through cycles
        // with the Image < / > buttons.
        final selectedImage = imageProvider.currentImage;

        return Column(
          children: [
            // Title bar with status indicator
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  StatusIndicator(status: gridProvider.currentStatus),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      selectedImage?.displayName ?? 'No image selected',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Rotation hint
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Tooltip(
                    message: 'Hold shift to rotate grid',
                    child: Icon(
                      Icons.refresh,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Hold Shift to rotate',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Image viewer
            const Expanded(
              child: ImageViewer(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (VersionInfo.gitVersion.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'GitHub:',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final uri = Uri.parse(VersionInfo.gitReleaseUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Text(
                    VersionInfo.gitVersion,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          Text(
            'Development build',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

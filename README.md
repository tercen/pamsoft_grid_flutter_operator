# Pamsoft Grid Checker

A Flutter desktop/web application for quality control review of automated fiducial grid fitting on Pamstation experiment TIFF images.

## Overview

Pamsoft Grid Checker is a QC tool designed for reviewing and adjusting the automated grid fitting performed on images from PamGene's Pamstation scientific instrument. The application allows operators to:

- View TIFF images from Pamstation experiments
- Review the automatically fitted 14x14 peptide grid with reference fiducials
- Manually adjust individual fiducial positions or the entire grid
- Navigate between wells and time points within an experiment
- Adjust image brightness and contrast for better visibility
- Re-run grid fitting algorithms when needed

## Features

- **Grid Overlay Visualization**: Interactive display of fiducial grid overlaid on experiment images
- **Drag-and-Drop Adjustment**: Move individual fiducials or the entire grid by dragging
- **Image Controls**: Brightness (-0.5 to 0.5) and contrast (0.2 to 4.0) adjustment
- **Experiment Navigation**: Browse between grid images and associated time points
- **Status Tracking**: Visual indicators showing processed vs. modified grid status
- **Light/Dark Theme**: Toggle between light and dark mode
- **Keyboard Navigation**: Arrow keys for quick grid navigation

## Operator Settings

This operator declares ten properties. **Only three of them affect what the
checker does.** The rest are carried so that a workflow migrating from the
Shiny grid checker keeps its settings, and so they remain available to the
gridding operator upstream — but changing them here has no effect on this app.

| Property | Effect in this operator |
|---|---|
| `Default Cycle` | **Active.** Which image is selected when a grid is opened: `highest` (default), `grid`, or a cycle number. |
| `Spot Pitch` | **Active.** Distance between spot centres, in pixels. `0` auto-detects from the image dimensions (Evolve3 552x413 → 17.0, Evolve2 697x520 → 21.5). Used to size drawn spots where the data carries no measured diameter. |
| `Spot Size` | **Active.** Fraction of the pitch a spot occupies. Used with Spot Pitch as above. |
| `Min Diameter` | **No effect here.** Bounds spot segmentation in the *gridding* operator. |
| `Max Diameter` | **No effect here.** As above. |
| `Saturation Limit` | **No effect here.** Used by the gridding/quantification steps. |
| `EdgeSensitivityLow` | **No effect here.** Segmentation parameter for the gridding operator. |
| `Edge Sensitivity` | **No effect here.** As above. |
| `Segmentation Method` | **No effect here.** As above. |
| `Rotation` | **No effect here.** Template rotation range for the gridding operator. |

### Why the inactive properties exist

The checker displays a grid fit that has already happened — it does not run
spot segmentation. The seven properties marked "no effect here" are inputs to
that earlier fitting step.

They behaved the same way in the Shiny operator this replaces: it declared the
same properties, parsed most of them into memory, and never read them back.
Two of them (`EdgeSensitivityLow`, `Segmentation Method`) had no parsing branch
at all there. They are preserved here so nothing is lost in the migration, not
because they became functional.

If one of these should start affecting the checker, that is new work: the app
would have to re-run segmentation, which neither this operator nor the Shiny
one has ever done.

## Getting Started

### Prerequisites

- Flutter SDK (3.0 or higher)
- Dart SDK

### Installation

```bash
# Clone the repository
git clone https://github.com/tercen/pamsoft_grid_flutter_operator.git

# Navigate to project directory
cd pamsoft_grid_flutter_operator

# Install dependencies
flutter pub get

# Run on web
flutter run -d chrome

# Run on desktop (Windows)
flutter run -d windows
```

## Architecture

The application follows clean architecture principles with:

- **Presentation Layer**: Flutter widgets with Provider state management
- **Domain Layer**: Service abstractions defining business logic interfaces
- **Implementation Layer**: Concrete service implementations (mock for MVP, real for production)

## License

Proprietary - PamGene International B.V.

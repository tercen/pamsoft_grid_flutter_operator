# Version Synchronization Guide

This document explains how to keep the app version in sync with Git tags.

## How It Works

The app displays its version number in the header, which is automatically read from `pubspec.yaml` at runtime using the `package_info_plus` package.

**Version Source:** `pubspec.yaml` line 4
```yaml
version: 0.0.1
```

**Display Location:** App header (AppBar) shows "Pamsoft Grid Checker v0.0.1"

## Updating the Version

When releasing a new version, follow these steps **in order**:

### 1. Update pubspec.yaml
```yaml
version: 0.0.2  # Change this to your new version
```

### 2. Rebuild the app
```bash
flutter build web
```

> ⚠️ **Do not add `--wasm`.** It builds with `dart2wasm` + the `skwasm` renderer, where
> `Image.memory()` fails to render the PNGs decoded from the TIFF images — you get "Failed to
> load image" placeholders while the grid overlay still draws on top, which looks like a data
> problem rather than a renderer problem.
>
> Plain `flutter build web` produces `dart2js` + `canvaskit`, which is what every working
> deployed build of this operator has used (verify with `"compileTarget":"dart2js"` in
> `build/web/flutter_bootstrap.js`).
>
> Re-enable `--wasm` only after verifying the skwasm renderer end-to-end against the
> operator's image pipeline.

### 3. Commit changes
```bash
git add pubspec.yaml pubspec.lock build/web/
git commit -m "Bump version to 0.0.2"
```

### 4. Create matching Git tag
```bash
git tag -a 0.0.2 -m "Version 0.0.2 - Description of changes"
```

### 5. Push everything
```bash
git push
git push origin 0.0.2
```

## Version Format

Use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (e.g., 1.0.0 → 2.0.0)
- **MINOR**: New features, backwards compatible (e.g., 1.0.0 → 1.1.0)
- **PATCH**: Bug fixes, backwards compatible (e.g., 1.0.0 → 1.0.1)

## Verification

After pushing, verify the version appears correctly:
1. The Git tag exists: `git tag -l`
2. The app displays the version in the header when running

## Current Version

**0.0.5** - Warnings on the operator properties the checker does not act on;
faster grid-to-grid navigation.

### History

| Version | Notes |
|---------|-------|
| 0.0.5 | Inert-setting warnings in README and `operator.json`; cross-grid image prefetch; `ciByImage` index for grid loads |
| 0.0.4 | Client feedback: header names the displayed image, `Default Cycle` property, nine operator properties restored, image display ~146ms → ~8ms, Evolve2 dimensions |
| 0.0.3 | `table.limit` paging for large datasets |
| 0.0.2 | Never tagged |
| 0.0.1 | Initial release with grid rotation feature |

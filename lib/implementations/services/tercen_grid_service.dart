import 'dart:typed_data';

import 'package:pamsoft_grid_flutter_operator/models/grid_data.dart';
import 'package:pamsoft_grid_flutter_operator/models/grid_configuration.dart';
import 'package:pamsoft_grid_flutter_operator/models/fiducial_position.dart';
import 'package:pamsoft_grid_flutter_operator/models/enums.dart';
import 'package:pamsoft_grid_flutter_operator/services/grid_service.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tercen_url_parser.dart';
import 'package:sci_tercen_context/sci_tercen_context.dart';
import 'package:tson/string_list.dart';

/// Tercen implementation of GridService.
///
/// Loads grid data from Tercen tables using OperatorContext (ctx.select/cselect/rselect).
/// Fetches ALL data once on first access and caches parsed results for all grid images.
class TercenGridService implements GridService {
  final ServiceFactoryBase _factory;
  final TercenUrlParser _urlParser;
  final GridService _mockService;

  final Map<String, GridData> _gridDataCache = {};
  final Map<String, GridStatus> _statusCache = {};

  /// Cached OperatorContext — created once and reused.
  AbstractOperatorContext? _ctx;

  /// Cached parsed Tercen data — fetched once, used for all grid images and save.
  _TercenDataCache? _tercenData;

  TercenGridService(this._factory, this._urlParser, this._mockService);

  /// Get or create the OperatorContext.
  Future<AbstractOperatorContext> _getContext() async {
    if (_ctx != null) return _ctx!;

    if (_urlParser.taskId == null) {
      throw Exception('No taskId found in URL');
    }

    print('📋 Creating OperatorContext for task: ${_urlParser.taskId}');
    _ctx = await OperatorContext.create(
      serviceFactory: _factory,
      taskId: _urlParser.taskId!,
    );
    print('✓ OperatorContext created');
    return _ctx!;
  }

  /// Fetch and parse ALL Tercen data once. Subsequent calls return cached result.
  Future<_TercenDataCache> _getTercenData() async {
    if (_tercenData != null) return _tercenData!;

    final ctx = await _getContext();

    print('📋 Fetching ALL Tercen data (one-time)...');

    // Build dataMap incrementally by paging through the main table.
    // Server caps a single select() at 1,600,000 rows (table.limit / Bad limit),
    // so we chunk under that ceiling and feed each chunk straight into dataMap.
    const selectChunkSize = 1000000;
    final mainSchema = await ctx.schema;
    final totalQtRows = mainSchema.nRows;
    final dataMap = <int, Map<int, double>>{};
    int qtRowsLoaded = 0;
    int qtOffset = 0;
    while (qtOffset < totalQtRows) {
      final remaining = totalQtRows - qtOffset;
      final thisLimit = remaining < selectChunkSize ? remaining : selectChunkSize;
      final qtChunk = await ctx.select(
        names: ['.ci', '.ri', '.y'],
        offset: qtOffset,
        limit: thisLimit,
      );
      if (qtChunk.nRows == 0) break;

      List ciValuesChunk = const [], riValuesChunk = const [];
      List<double> yValuesChunk = const [];
      for (final col in qtChunk.columns) {
        switch (col.name) {
          case '.ci':
            ciValuesChunk = col.values as List;
          case '.ri':
            riValuesChunk = col.values as List;
          case '.y':
            yValuesChunk =
                (col.values as List).map((v) => (v as num).toDouble()).toList();
        }
      }
      for (int i = 0; i < ciValuesChunk.length; i++) {
        final ci = (ciValuesChunk[i] as num).toInt();
        final ri = (riValuesChunk[i] as num).toInt();
        dataMap.putIfAbsent(ci, () => {});
        dataMap[ci]![ri] = yValuesChunk[i];
      }

      qtRowsLoaded += qtChunk.nRows;
      qtOffset += qtChunk.nRows;
      print(
          '  qtData chunk @ offset=${qtOffset - qtChunk.nRows}: ${qtChunk.nRows} rows ($qtRowsLoaded / $totalQtRows)');
    }
    print('✓ qtData: $qtRowsLoaded rows');

    final colData = await ctx.cselect();
    print('✓ colData: ${colData.nRows} rows, ${colData.columns.length} columns');

    final rowData = await ctx.rselect();
    print('✓ rowData: ${rowData.nRows} rows, ${rowData.columns.length} columns');

    // Build column metadata map: ci index -> {Image, spotRow, spotCol, ID, ...}
    final colMetadata = <int, Map<String, dynamic>>{};
    for (final col in colData.columns) {
      final values = col.values as List?;
      if (values == null) continue;
      final fieldName = col.name.contains('.')
          ? col.name.split('.').last
          : col.name;
      for (int i = 0; i < values.length; i++) {
        colMetadata.putIfAbsent(i, () => {});
        colMetadata[i]![fieldName] = values[i];
      }
    }
    print('✓ Column metadata: ${colMetadata.length} entries');

    // Build row metadata map: ri index -> variable name
    final rowMetadata = <int, String>{};
    for (final col in rowData.columns) {
      final values = col.values as List?;
      if (values == null) continue;
      for (int i = 0; i < values.length; i++) {
        final varName = values[i]?.toString() ?? '';
        rowMetadata[i] = varName.contains('.')
            ? varName.split('.').last
            : varName;
      }
    }
    print('✓ Row metadata: $rowMetadata');

    print('✓ Data map: ${dataMap.length} spots, $qtRowsLoaded total rows');

    // Build image lookup: imageName -> list of ci indices
    final allImages = <String>{};
    for (final meta in colMetadata.values) {
      final img = meta['Image']?.toString();
      if (img != null) allImages.add(img);
    }
    print('✓ Unique images in data: ${allImages.length}');

    _tercenData = _TercenDataCache(
      colMetadata: colMetadata,
      rowMetadata: rowMetadata,
      dataMap: dataMap,
      allImages: allImages,
    );
    return _tercenData!;
  }

  @override
  Future<GridData> loadGridData(String gridImageId) async {
    if (_gridDataCache.containsKey(gridImageId)) {
      return _gridDataCache[gridImageId]!;
    }

    try {
      print('🔍 Loading grid for $gridImageId');

      final data = await _getTercenData();
      final gridData = _buildGridDataForImage(data, gridImageId);

      _gridDataCache[gridImageId] = gridData;
      _statusCache[gridImageId] = GridStatus.processed;

      print('✓ ${gridData.fiducials.length} fiducials for $gridImageId');
      return gridData;
    } catch (e, stackTrace) {
      print('❌ ERROR loading grid data: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Build GridData for a single image from the cached Tercen data.
  GridData _buildGridDataForImage(_TercenDataCache data, String gridImageId) {
    // Resolve gridImageId to matching Image in the data
    String? resolvedImageName;
    if (data.allImages.contains(gridImageId)) {
      resolvedImageName = gridImageId;
    } else {
      final parts = gridImageId.split('_');
      if (parts.length >= 4) {
        final prefix = parts.sublist(0, 4).join('_');
        for (final img in data.allImages) {
          if (img.startsWith(prefix)) {
            resolvedImageName = img;
            break;
          }
        }
      }
    }

    final fiducials = <FiducialPosition>[];

    if (resolvedImageName != null) {
      for (final entry in data.dataMap.entries) {
        final ci = entry.key;
        final riYMap = entry.value;

        final colMeta = data.colMetadata[ci];
        if (colMeta == null) continue;

        final imageName = colMeta['Image']?.toString() ?? '';
        if (imageName != resolvedImageName) continue;

        final spotRow = (colMeta['spotRow'] as num?)?.toDouble() ?? 0.0;
        final spotCol = (colMeta['spotCol'] as num?)?.toDouble() ?? 0.0;
        final id = colMeta['ID'] as String? ?? '';
        final grdImageNameUsed = colMeta['grdImageNameUsed']?.toString() ?? '';

        double? gridX;
        double? gridY;
        double? diameter;
        int? manual;
        int? bad;
        int? empty;

        for (final riEntry in riYMap.entries) {
          final ri = riEntry.key;
          final y = riEntry.value;
          final varName = data.rowMetadata[ri];
          if (varName == null || varName.isEmpty) continue;

          switch (varName) {
            case 'gridX':
              gridX = y;
            case 'gridY':
              gridY = y;
            case 'diameter':
              diameter = y;
            case 'manual':
              manual = y.toInt();
            case 'bad':
              bad = y.toInt();
            case 'empty':
              empty = y.toInt();
          }
        }

        if (gridX != null && gridY != null) {
          fiducials.add(FiducialPosition(
            id: '$ci',
            ci: ci,
            imageName: imageName,
            grdImageNameUsed: grdImageNameUsed,
            row: spotRow.toInt(),
            col: spotCol.toInt(),
            baseX: gridY,
            baseY: gridX,
            diameter: diameter ?? 0.0,
            isReference: id == '#REF',
            isManual: manual == 1,
            isBad: bad == 1,
            isEmpty: empty == 1,
          ));
        }
      }
    }

    final config = GridConfiguration.evolve3(
      imageWidth: 552,
      imageHeight: 413,
    );

    return GridData(
      gridImageId: gridImageId,
      configuration: config,
      fiducials: fiducials,
      globalOffsetX: 0,
      globalOffsetY: 0,
    );
  }

  @override
  Future<void> saveGridAdjustments(String gridImageId, GridData gridData) async {
    _gridDataCache[gridImageId] = gridData;
    _statusCache[gridImageId] = GridStatus.modified;
  }

  @override
  Future<GridData> loadDefaultGrid() async {
    return _mockService.loadDefaultGrid();
  }

  @override
  Future<GridData> runGridProcessing(String gridImageId) async {
    await Future.delayed(const Duration(seconds: 5));
    _statusCache[gridImageId] = GridStatus.processed;
    return _gridDataCache[gridImageId] ?? await loadGridData(gridImageId);
  }

  @override
  GridStatus getGridStatus(String gridImageId) {
    return _statusCache[gridImageId] ?? GridStatus.processed;
  }

  @override
  void setGridStatus(String gridImageId, GridStatus status) {
    _statusCache[gridImageId] = status;
  }

  @override
  Future<void> saveAllGrids(List<String> allGridImageIds) async {
    final ctx = await _getContext();

    print('📤 saveAllGrids: Using cached Tercen data...');
    await ctx.progress('Loading data...', actual: 0, total: 3);

    // 1. Get cached data (already fetched during loadGridData calls)
    final data = await _getTercenData();

    // 2. Ensure all grid images are loaded (lazy load any unvisited ones)
    for (final gridImageId in allGridImageIds) {
      if (!_gridDataCache.containsKey(gridImageId)) {
        print('  Loading unvisited grid: $gridImageId');
        _gridDataCache[gridImageId] = _buildGridDataForImage(data, gridImageId);
      }
    }

    await ctx.progress('Building output...', actual: 1, total: 3);

    // 3. Build position lookup for modified grids:
    //    grdImageNameUsed -> { "row_col" -> modified fiducial data }
    // This allows applying grid changes to ALL images sharing the same grid.
    final modifiedGridLookup = <String, Map<String, _ModifiedSpot>>{};
    for (final entry in _gridDataCache.entries) {
      final gridImageId = entry.key;
      final gridData = entry.value;

      // Only include grids that were actually modified
      if (_statusCache[gridImageId] != GridStatus.modified) continue;

      final spotLookup = <String, _ModifiedSpot>{};
      for (final f in gridData.fiducials) {
        // Compute final display position
        final displayX = f.baseX + gridData.globalOffsetX + f.individualOffsetX;
        final displayY = f.baseY + gridData.globalOffsetY + f.individualOffsetY;

        // Coordinate swap back: display X → Tercen gridY, display Y → Tercen gridX
        spotLookup['${f.row}_${f.col}'] = _ModifiedSpot(
          tercenGridX: displayY,
          tercenGridY: displayX,
          diameter: f.diameter,
          isManual: f.isManual,
          isBad: f.isBad,
          isEmpty: f.isEmpty,
          rotation: gridData.rotation,
        );
      }

      modifiedGridLookup[gridImageId] = spotLookup;
    }

    print('  Modified grids: ${modifiedGridLookup.keys.toList()}');

    // 4. Find ri indices for each variable name
    final riForVar = <String, int>{};
    for (final entry in data.rowMetadata.entries) {
      riForVar[entry.value] = entry.key;
    }

    // 5. Build output arrays — one row per spot (unique .ci)
    // The Shiny uses .ci from gridY rows; we use all unique .ci values.
    final allCis = data.dataMap.keys.toList()..sort();

    final outCi = <int>[];
    final outGridX = <double>[];
    final outGridY = <double>[];
    final outFixedX = <double>[];
    final outFixedY = <double>[];
    final outDiameter = <double>[];
    final outManual = <double>[];
    final outBad = <double>[];
    final outEmpty = <double>[];
    final outRotation = <double>[];
    final outGrdImageNameUsed = <String>[];
    final outImage = <String>[];

    for (final ci in allCis) {
      final colMeta = data.colMetadata[ci];
      if (colMeta == null) continue;

      final riYMap = data.dataMap[ci]!;
      final spotRow = (colMeta['spotRow'] as num?)?.toInt() ?? 0;
      final spotCol = (colMeta['spotCol'] as num?)?.toInt() ?? 0;
      final imageName = colMeta['Image']?.toString() ?? '';
      final grdImageName = colMeta['grdImageNameUsed']?.toString() ?? '';

      // Check if this spot's grid was modified
      final modifiedSpots = modifiedGridLookup[grdImageName];
      final modifiedSpot = modifiedSpots?['${spotRow}_$spotCol'];

      if (modifiedSpot != null) {
        // Use modified positions (propagated from the grid image to all images)
        outCi.add(ci);
        outGridX.add(modifiedSpot.tercenGridX);
        outGridY.add(modifiedSpot.tercenGridY);
        outFixedX.add(modifiedSpot.tercenGridX); // manual: fixed = current
        outFixedY.add(modifiedSpot.tercenGridY);
        outDiameter.add(modifiedSpot.diameter);
        outManual.add(modifiedSpot.isManual ? 1.0 : 0.0);
        outBad.add(modifiedSpot.isBad ? 1.0 : 0.0);
        outEmpty.add(modifiedSpot.isEmpty ? 1.0 : 0.0);
        outRotation.add(modifiedSpot.rotation);
        outGrdImageNameUsed.add(grdImageName);
        outImage.add(imageName);
      } else {
        // Use original values from Tercen data
        outCi.add(ci);
        outGridX.add(riYMap[riForVar['gridX']] ?? 0.0);
        outGridY.add(riYMap[riForVar['gridY']] ?? 0.0);
        outFixedX.add(riYMap[riForVar['grdXFixedPosition']] ?? 0.0);
        outFixedY.add(riYMap[riForVar['grdYFixedPosition']] ?? 0.0);
        outDiameter.add(riYMap[riForVar['diameter']] ?? 0.0);
        outManual.add(riYMap[riForVar['manual']] ?? 0.0);
        outBad.add(riYMap[riForVar['bad']] ?? 0.0);
        outEmpty.add(riYMap[riForVar['empty']] ?? 0.0);
        outRotation.add(riYMap[riForVar['grdRotation']] ?? 0.0);
        outGrdImageNameUsed.add(grdImageName);
        outImage.add(imageName);
      }
    }

    print('  Output: ${outCi.length} rows');

    // 6. Add namespace prefixes to column names
    final ns = await ctx.namespace;
    print('  Operator namespace: "$ns"');
    final nameMap = await ctx.addNamespace([
      'gridX', 'gridY', 'grdXFixedPosition', 'grdYFixedPosition',
      'diameter', 'manual', 'bad', 'empty', 'grdRotation',
      'grdImageNameUsed', 'Image',
    ]);
    print('  Namespaced columns: $nameMap');

    // 7. Build the output Table with TypedData on column.values
    //    TSON encoder requires dart:typed_data (Int32List, Float64List) and
    //    CStringList for correct binary serialization (LIST_INT32_TYPE,
    //    LIST_FLOAT64_TYPE, LIST_STRING_TYPE). Regular Dart lists serialize
    //    as generic LIST_TYPE which the server rejects.
    final nRows = outCi.length;
    final table = Table();
    table.nRows = nRows;

    // .ci column (system column — no namespace prefix)
    final ciCol = Column();
    ciCol.name = '.ci';
    ciCol.type = 'int32';
    ciCol.nRows = nRows;
    ciCol.values = Int32List.fromList(outCi);
    final ciVals = I32Values();
    ciVals.values.addAll(outCi);
    ciCol.cValues = ciVals;
    table.columns.add(ciCol);

    // Double columns: column.values = Float64List for correct TSON encoding
    void addDoubleCol(String name, List<double> values) {
      final col = Column();
      col.name = nameMap[name]!;
      col.type = 'double';
      col.nRows = nRows;
      col.values = Float64List.fromList(values);
      final f64 = F64Values();
      f64.values.addAll(values);
      col.cValues = f64;
      table.columns.add(col);
    }

    addDoubleCol('gridX', outGridX);
    addDoubleCol('gridY', outGridY);
    addDoubleCol('grdXFixedPosition', outFixedX);
    addDoubleCol('grdYFixedPosition', outFixedY);
    addDoubleCol('diameter', outDiameter);
    addDoubleCol('manual', outManual);
    addDoubleCol('bad', outBad);
    addDoubleCol('empty', outEmpty);
    addDoubleCol('grdRotation', outRotation);

    // String columns: column.values = CStringList for correct TSON encoding
    void addStringCol(String name, List<String> values) {
      final col = Column();
      col.name = nameMap[name]!;
      col.type = 'string';
      col.nRows = nRows;
      col.values = CStringList.fromList(values);
      final str = StrValues();
      str.values.addAll(values);
      col.cValues = str;
      table.columns.add(col);
    }

    addStringCol('grdImageNameUsed', outGrdImageNameUsed);
    addStringCol('Image', outImage);

    print('  Table built: ${table.nRows} rows, ${table.columns.length} columns');
    for (final col in table.columns) {
      print('    ${col.name} (${col.cValues.runtimeType})');
    }

    // 8. Save to Tercen
    await ctx.progress('Saving to Tercen...', actual: 2, total: 3);
    print('📤 Saving table to Tercen...');

    await ctx.saveTable(table);

    await ctx.progress('Done', actual: 3, total: 3);
    print('✓ Save complete!');
  }
}

/// Cached parsed Tercen data — fetched once from ctx.select/cselect/rselect.
class _TercenDataCache {
  /// ci index -> {Image, spotRow, spotCol, ID, grdImageNameUsed, ...}
  final Map<int, Map<String, dynamic>> colMetadata;

  /// ri index -> variable name (gridX, gridY, diameter, etc.)
  final Map<int, String> rowMetadata;

  /// ci -> {ri -> y value}
  final Map<int, Map<int, double>> dataMap;

  /// All unique image names found in the data.
  final Set<String> allImages;

  _TercenDataCache({
    required this.colMetadata,
    required this.rowMetadata,
    required this.dataMap,
    required this.allImages,
  });
}

/// Helper class for modified spot data in Tercen coordinate space.
class _ModifiedSpot {
  final double tercenGridX;
  final double tercenGridY;
  final double diameter;
  final bool isManual;
  final bool isBad;
  final bool isEmpty;
  final double rotation;

  _ModifiedSpot({
    required this.tercenGridX,
    required this.tercenGridY,
    required this.diameter,
    required this.isManual,
    required this.isBad,
    required this.isEmpty,
    required this.rotation,
  });
}

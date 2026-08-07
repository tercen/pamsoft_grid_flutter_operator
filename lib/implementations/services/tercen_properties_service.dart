import 'package:pamsoft_grid_flutter_operator/models/operator_properties.dart';
import 'package:pamsoft_grid_flutter_operator/services/properties_service.dart';
import 'package:pamsoft_grid_flutter_operator/utils/tercen_url_parser.dart';
import 'package:sci_tercen_context/sci_tercen_context.dart';

/// Reads operator properties from the Tercen task's operator settings.
///
/// Mirrors Shiny's `get_operator_props()`, which walked
/// `ctx$query$operatorSettings$operatorRef$propertyValues`. The SDK's
/// `opDoubleValue`/`opStringValue` do that walk for us and apply the default
/// when a property is absent or blank.
class TercenPropertiesService implements PropertiesService {
  final ServiceFactoryBase _factory;
  final TercenUrlParser _urlParser;

  OperatorProperties? _cached;

  TercenPropertiesService(this._factory, this._urlParser);

  @override
  Future<OperatorProperties> getProperties() async {
    if (_cached != null) return _cached!;

    if (_urlParser.taskId == null || _urlParser.taskId!.isEmpty) {
      print('⚠️ No taskId — using default operator properties');
      return _cached = OperatorProperties.defaults;
    }

    try {
      final ctx = await OperatorContext.create(
        serviceFactory: _factory,
        taskId: _urlParser.taskId!,
      );

      const d = OperatorProperties.defaults;
      final props = OperatorProperties(
        spotPitch:
            await ctx.opDoubleValue('Spot Pitch', defaultValue: d.spotPitch),
        spotSize:
            await ctx.opDoubleValue('Spot Size', defaultValue: d.spotSize),
        minDiameter: await ctx.opDoubleValue('Min Diameter',
            defaultValue: d.minDiameter),
        maxDiameter: await ctx.opDoubleValue('Max Diameter',
            defaultValue: d.maxDiameter),
        saturationLimit: await ctx.opDoubleValue('Saturation Limit',
            defaultValue: d.saturationLimit),
        edgeSensitivityLow: await ctx.opDoubleValue('EdgeSensitivityLow',
            defaultValue: d.edgeSensitivityLow),
        edgeSensitivity: await ctx.opDoubleValue('Edge Sensitivity',
            defaultValue: d.edgeSensitivity),
        segmentationMethod: await ctx.opStringValue('Segmentation Method',
            defaultValue: d.segmentationMethod),
        rotation:
            await ctx.opStringValue('Rotation', defaultValue: d.rotation),
        defaultCycle: await ctx.opStringValue('Default Cycle',
            defaultValue: d.defaultCycle),
      );

      print('✓ Operator properties: $props');
      return _cached = props;
    } catch (e) {
      // A property read failure must not take the viewer down — the checker
      // only needs Spot Pitch/Spot Size, and both have workable defaults.
      print('⚠️ Could not read operator properties ($e) — using defaults');
      return _cached = OperatorProperties.defaults;
    }
  }
}

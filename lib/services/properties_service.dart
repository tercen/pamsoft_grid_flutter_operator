import 'package:pamsoft_grid_flutter_operator/models/operator_properties.dart';

/// Abstract interface for reading the operator's declared properties.
abstract class PropertiesService {
  /// Loads the operator properties, falling back to declared defaults when
  /// they cannot be read (dev mode, missing task, transport error).
  ///
  /// Implementations cache — this is safe to call repeatedly.
  Future<OperatorProperties> getProperties();
}

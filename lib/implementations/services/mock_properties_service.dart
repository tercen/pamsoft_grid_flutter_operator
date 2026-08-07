import 'package:pamsoft_grid_flutter_operator/models/operator_properties.dart';
import 'package:pamsoft_grid_flutter_operator/services/properties_service.dart';

/// Mock properties service — always returns the declared defaults.
class MockPropertiesService implements PropertiesService {
  @override
  Future<OperatorProperties> getProperties() async =>
      OperatorProperties.defaults;
}
